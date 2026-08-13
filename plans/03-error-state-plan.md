# reference-service: configurable error-state (fault injection)

## Context

`reference-service` currently always behaves correctly — `/calc` always
computes, `/healthz` always returns `200`. This plan adds a deliberate,
configurable failure mode: after a configurable number of successful
`/calc` calls (`call_threshold`), the service flips into an "error state"
where both `/calc` and `/healthz` return `503` for a configurable duration
(`error_state_duration_seconds`, default `120`), then automatically
recovers. `call_threshold <= 0` (the default) disables the feature
entirely, so existing behavior is unchanged unless someone deliberately
turns it on.

This gives the project its first actual fault-injection knob on
`reference-service`, toggleable on demand via a new standalone GitHub
Actions workflow — without needing a full rebuild/redeploy of the service
image, since it only changes ECS task-definition environment variables.

Alongside that, the k6 smoke test's run length
(`k6/scripts/reference-service/smoke.js`'s hardcoded `duration: '30s'`) is
made configurable too, defaulting to 3 minutes — long enough to actually
observe an error-state trip/recovery cycle during a live k6 run, which a
30s run is too short for at the default 120s error duration.

This is scoped purely to `reference-service`. We're executing this **step
by step, asking for validation of each step before continuing**, checking
off each box in this file as it's validated. Progress notes go in
`plans/03-error-state-progress.txt`. If resuming this plan in a later
session: check which boxes are already checked, read
`03-error-state-progress.txt` for notes, and pick up at the first
unchecked step.

## Design decisions (locked in, don't re-litigate on resume)

- **What counts toward `call_threshold`**: only `/calc` calls that return
  `200` (a real, successful calculation). `400`s (bad operator, bad
  operands, division by zero) are free and don't count.
- **The counter freezes during error state.** Calls to `/calc` while in
  error state return `503` immediately without touching the counter. The
  counter only resets to `0` when the duration elapses and the service
  exits error state.
- **The threshold-th successful call still succeeds** (returns `200`).
  Error state begins immediately after that call completes, so it's the
  `(call_threshold + 1)`-th call that first sees `503`.
- **Both `/calc` and `/healthz` return `503`** while in error state (per
  the original request). `/healthz`'s body stays plain text (`"ok"` today
  → some plain-text error body), matching its existing non-JSON style.
  `/calc`'s `503` reuses the existing `writeJSONError` helper for
  consistency with its other error responses.
- **Lazy state transitions, no background goroutine/timer.** Each request
  (either endpoint) compares `time.Now()` against a stored `errorUntil`
  timestamp; if it's passed, the handler resets state (exit error state,
  counter → `0`) before proceeding. This matches the service's current
  total absence of goroutines/timers and keeps the change minimal and
  testable (no timer-related flakiness in tests).
- **Config via plain `os.Getenv` + fallback**, matching the existing
  `LISTEN_ADDR` pattern in `main.go` — no new config struct/library
  introduced for two more values: `CALL_THRESHOLD` (int, default `0`) and
  `ERROR_STATE_DURATION_SECONDS` (int, default `120`).
- **First shared mutable state in this service** — a `sync.Mutex`-guarded
  struct is required since concurrent requests will otherwise race on the
  counter/error-state fields.
- **Known interaction with the existing container-level health check**
  (from `plans/02-healthcheck-plan.md`: `interval 15s / timeout 5s /
  retries 3 / startPeriod 10s`): once `/healthz` starts returning `503`,
  ECS marks the container `UNHEALTHY` roughly 45-60s later and replaces
  the task — likely *before* a longer `error_state_duration_seconds`
  (e.g. the 120s default) would have elapsed on its own. This is expected,
  not a bug: task replacement is itself a valid recovery path (and a nice
  demo of ECS self-healing), but the configured "seconds until healthy"
  may end up bounded by whichever recovery path fires first. Worth
  observing directly during live verification (step 13).
- **No changes needed in `terraform/modules/ecs-service`** — the
  `containers[*].environment` field already exists in that module's
  schema and already passes straight through into the container
  definition JSON (confirmed: `main.tf:13`,
  `variables.tf:57-60`). Only the scenario-level files need to change.
- **New Terraform variables default to today's behavior**
  (`call_threshold = 0`), so merging the code/Terraform changes through
  the normal pipeline is a no-op for the running service until someone
  deliberately runs the new toggle workflow.
- **The new standalone workflow applies directly** (`apply: true` on
  `workflow_dispatch`, no plan-then-approve gate), mirroring the existing
  `workflow_dispatch: {}` escape hatch already in
  `scenario-reference-service.yml` (added in commit `661825b`). Consistent
  with established convention — it's a human manually triggering a CI
  workflow, not Claude running Terraform directly.
- **k6 run duration uses k6's own built-in `K6_DURATION` env var
  override** — k6 automatically lets any exported `options` field be
  overridden by a same-named `K6_<OPTION>` environment variable at
  runtime, at higher priority than the script's exported `options`. So no
  duration-parsing code is added to `smoke.js` at all; it keeps a plain
  `duration: '3m'` default (bumped from `30s`), and the new
  `k6_test_duration` Terraform variable just sets `K6_DURATION` on the
  k6-runner container.
- **`k6_test_duration` gets a Terraform variable but no dedicated
  workflow-dispatch input** — unlike `call_threshold`/
  `error_state_duration_seconds`, which the user explicitly asked to be
  easy to toggle standalone, k6 run length wasn't asked to be toggled
  on-demand. It's still reachable ad hoc through the generic
  `tf-var-overrides` mechanism (step 9) if ever needed, without adding a
  bespoke input to the dedicated fault-config workflow. Easy to add a
  third dedicated input later if wanted.

## Steps

- [x] **0. Write this plan to `plans/03-error-state-plan.md`.**

- [x] **1. `services/reference-service/main.go` — error-state logic.**
  Add near the existing type definitions (after `errorResponse`, line 28):
  ```go
  type serviceState struct {
      mu            sync.Mutex
      callThreshold int
      errorDuration time.Duration
      count         int
      errorUntil    time.Time // zero value = not in error state
  }

  func newServiceState(callThreshold int, errorDuration time.Duration) *serviceState {
      return &serviceState{callThreshold: callThreshold, errorDuration: errorDuration}
  }

  // inErrorState reports whether the service is currently in its error
  // state, lazily resetting (exiting error state, counter -> 0) if the
  // configured duration has elapsed since entry.
  func (s *serviceState) inErrorState(now time.Time) bool {
      s.mu.Lock()
      defer s.mu.Unlock()
      if s.errorUntil.IsZero() {
          return false
      }
      if now.Before(s.errorUntil) {
          return true
      }
      s.errorUntil = time.Time{}
      s.count = 0
      return false
  }

  // recordSuccess counts one successful /calc call, entering error state
  // once callThreshold is reached. No-op if callThreshold <= 0.
  func (s *serviceState) recordSuccess(now time.Time) {
      if s.callThreshold <= 0 {
          return
      }
      s.mu.Lock()
      defer s.mu.Unlock()
      s.count++
      if s.count >= s.callThreshold {
          s.errorUntil = now.Add(s.errorDuration)
      }
  }
  ```
  Convert `healthzHandler` and `calcHandler` into methods on
  `*serviceState`:
  - `(s *serviceState) healthzHandler(w, r)`: if `s.inErrorState(time.Now())`,
    write `503` + a plain-text error body; else existing `200 ok` behavior.
  - `(s *serviceState) calcHandler(w, r)`: **first line of the function**,
    check `s.inErrorState(time.Now())` → `writeJSONError(w,
    http.StatusServiceUnavailable, "service is in error state")` and
    return, before any method/param validation (so *every* call during
    error state gets `503`, regardless of input validity). Otherwise, run
    existing logic unchanged; on the success path only (just before
    writing the `200` response), call `s.recordSuccess(time.Now())`.
  In `main()`: read the two new env vars next to the existing
  `LISTEN_ADDR` read —
  ```go
  callThreshold := 0
  if v := os.Getenv("CALL_THRESHOLD"); v != "" {
      if n, err := strconv.Atoi(v); err == nil {
          callThreshold = n
      }
  }
  errorDurationSeconds := 120
  if v := os.Getenv("ERROR_STATE_DURATION_SECONDS"); v != "" {
      if n, err := strconv.Atoi(v); err == nil {
          errorDurationSeconds = n
      }
  }
  state := newServiceState(callThreshold, time.Duration(errorDurationSeconds)*time.Second)
  ```
  Update mux registration to `mux.HandleFunc("/healthz", state.healthzHandler)`
  and `mux.HandleFunc("/calc", state.calcHandler)`. `runHealthcheck` and
  the CLI `healthcheck` subcommand branch are unaffected (they just probe
  `/healthz` over HTTP and check status code — a `503` during error state
  correctly makes `./reference-service healthcheck` exit `1`, which is
  exactly the desired ECS-container-health interaction called out above).
  Add `"sync"` to imports.

- [x] **2. `services/reference-service/main_test.go` — update + add
  tests.** Existing tests call `healthzHandler`/`calcHandler` directly as
  free functions (lines 12-127) — update each call site to construct a
  `state := newServiceState(0, 0)` (threshold `0` = disabled, preserves
  today's always-succeeds behavior) and call `state.healthzHandler(...)` /
  `state.calcHandler(...)`. `TestRunHealthcheckSuccess`/`Failure` (lines
  130-156) also need their `mux.HandleFunc("/healthz", ...)` updated to a
  `state.healthzHandler`. Add new tests:
  - `TestCalcHandlerErrorState`: `state := newServiceState(2, 50*time.Millisecond)`.
    Two successful calls → both `200`. Third call → `503`, body mentions
    "error state". Confirm a bad-operand call in between the two
    successes doesn't count (still takes exactly 2 successes to trip).
  - `TestHealthzHandlerErrorState`: same setup, confirm `/healthz` also
    returns `503` once tripped.
  - `TestErrorStateAutoRecovery`: trip the threshold, sleep past the
    (short, millisecond-scale) duration, confirm both `/calc` and
    `/healthz` return to normal, and confirm the counter reset (need
    `callThreshold` more successful calls again to re-trip, not just `1`).
  - `TestCalcHandlerThresholdDisabled`: `newServiceState(0, ...)`, many
    successful calls in a loop, confirm never `503`.
  Run `go test ./...` in `services/reference-service`, confirm all pass.

- [ ] **3. `services/reference-service/README.md` — docs.** New
  `## Error-state simulation` section: document `CALL_THRESHOLD` (default
  `0`, disabled) and `ERROR_STATE_DURATION_SECONDS` (default `120`) env
  vars, the counting rule (successful `/calc` calls only, frozen during
  error state), and that both `/calc` and `/healthz` return `503` while
  tripped, auto-recovering after the configured duration.

- [ ] **4. Local verification.** `go build -o reference-service . &&
  CALL_THRESHOLD=3 ERROR_STATE_DURATION_SECONDS=10 ./reference-service`,
  then in another terminal: hit `/calc?op1=1&op2=1&operator=add` four
  times — first three `200`, fourth `503`; `curl -i localhost:8080/healthz`
  → `503`; wait 10s; repeat both → back to `200`. Then Docker: `docker
  build`, `docker run -e CALL_THRESHOLD=3 -e
  ERROR_STATE_DURATION_SECONDS=10 ...`, repeat the same curl sequence
  against the container to confirm env vars flow through correctly in the
  distroless runtime.

- [ ] **5. `k6/scripts/reference-service/smoke.js` — configurable run
  duration.** Change `duration: '30s'` (line 8) to `duration: '3m'`, with
  a one-line comment noting it's overridable via k6's built-in
  `K6_DURATION` env var (non-obvious behavior worth flagging since
  nothing in the script itself shows the override happening).

- [ ] **6. `terraform/scenarios/reference-service/variables.tf` — new
  variables.** Add, following the existing style (`image_tag`,
  `desired_count`, etc.):
  ```hcl
  variable "call_threshold" {
    description = "Number of successful /calc calls before reference-service enters its error state. 0 disables fault injection."
    type        = number
    default     = 0
  }

  variable "error_state_duration_seconds" {
    description = "Seconds reference-service stays in its error state before auto-recovering."
    type        = number
    default     = 120
  }

  variable "k6_test_duration" {
    description = "k6 smoke-test run length, e.g. \"3m\". Passed through as K6_DURATION, which k6 natively uses to override the script's exported options.duration."
    type        = string
    default     = "3m"
  }
  ```

- [ ] **7. `terraform/scenarios/reference-service/service.tf` — wire
  error-state env vars into the container.** On the `reference-service`
  container entry (alongside `health_check`), add:
  ```hcl
  environment = [
    { name = "CALL_THRESHOLD", value = tostring(var.call_threshold) },
    { name = "ERROR_STATE_DURATION_SECONDS", value = tostring(var.error_state_duration_seconds) }
  ]
  ```
  No changes to `terraform.tfvars` — leaving these unset uses the `0`/`120`
  defaults, so a normal `terraform apply` through the CI/CD pipeline keeps
  fault injection off.

- [ ] **8. `terraform/scenarios/reference-service/k6.tf` — wire
  `K6_DURATION` into the k6-runner container.** Add to the existing
  `environment` list (alongside `BASE_URL`):
  ```hcl
  { name = "K6_DURATION", value = var.k6_test_duration }
  ```

- [ ] **9. `.github/workflows/terraform-scenario.yml` — generic var
  override input.** Add one new optional input, kept generic/reusable
  (not reference-service-specific), following the file's existing
  "generic on working-directory" design:
  ```yaml
  tf-var-overrides:
    description: "Optional newline-separated KEY=VALUE pairs, exported as TF_VAR_KEY before plan, e.g. for one-off fault-injection runs."
    required: false
    type: string
    default: ""
  ```
  In the `plan` job, before the `terraform plan` step, add a step that
  reads `inputs.tf-var-overrides` via the job's `env:` (not direct string
  interpolation into the shell command, to avoid script-injection) and
  exports each pair into `$GITHUB_ENV` as `TF_VAR_<key>`:
  ```yaml
  - name: Export tf-var-overrides
    if: inputs.tf-var-overrides != ''
    env:
      TF_VAR_OVERRIDES: ${{ inputs.tf-var-overrides }}
    run: |
      while IFS='=' read -r key value; do
        [ -z "$key" ] && continue
        echo "TF_VAR_${key}=${value}" >> "$GITHUB_ENV"
      done <<< "$TF_VAR_OVERRIDES"
  ```
  Only the `plan` job needs this — `terraform apply tfplan` replays a
  saved plan and doesn't re-read variables.

- [ ] **10. New `.github/workflows/set-reference-service-fault-config.yml`
  — the standalone toggle workflow.** `workflow_dispatch` with two typed
  inputs, `call_threshold` (default `"0"`) and
  `error_state_duration_seconds` (default `"120"`), calling
  `terraform-scenario.yml` with `apply: true`,
  `working-directory: terraform/scenarios/reference-service`, and
  `tf-var-overrides` built from the two inputs. This workflow only runs
  Terraform (no build/deploy/k6 steps) — changing the container's
  environment values produces a new task-definition revision, and since
  `aws_ecs_service.this.task_definition` references that revision's ARN
  directly (`terraform/modules/ecs-service/main.tf:86`), `terraform
  apply` alone triggers ECS to roll a fresh deployment picking up the new
  values — no separate `deploy-service.yml` run needed. `k6_test_duration`
  is deliberately *not* one of this workflow's inputs (see design
  decisions) but can still be set via `tf-var-overrides` directly if ever
  needed for a one-off run.

- [ ] **11. `terraform plan` review.** Run `terraform plan` in
  `terraform/scenarios/reference-service` (user runs this, per standing
  preference). Expect only an additive task-definition revision on both
  the `reference-service` and `k6-runner` task definitions (new
  `environment` entries), no destroy/replace.

- [ ] **12. Ship the structural changes through the normal pipeline.**
  Commit, push, open a PR (user handles all git operations) covering
  `main.go`, `main_test.go`, `README.md`, `smoke.js`, `variables.tf`,
  `service.tf`, `k6.tf`, `terraform-scenario.yml`, and the new workflow
  file. Merging triggers `scenario-reference-service.yml` with the
  default vars (`call_threshold=0`, `error_state_duration_seconds=120`,
  `k6_test_duration="3m"`), so fault injection stays off and the k6 task
  simply runs three minutes instead of thirty seconds.

- [ ] **13. Live verification.** Trigger the new
  `set-reference-service-fault-config.yml` workflow (e.g.
  `call_threshold=5`, `error_state_duration_seconds=30`). Confirm a new
  task-definition revision and rolling deployment. Then run the k6 smoke
  test (now running for 3 minutes by default, long enough to span the
  trip/recovery cycle) and confirm its logs show early iterations
  succeeding, a run of `503`s once past the 5th successful `/calc` call,
  and a return to `200`s after ~30s; watch `aws ecs describe-tasks`
  `healthStatus` flip to `UNHEALTHY` once `/healthz` starts failing
  (~45-60s in, per the existing container health-check cadence) and note
  whether ECS replaces the task before the app's own 30s timer would have
  recovered it (the interaction flagged in design decisions above).
  Finally, re-run the workflow with `call_threshold=0` to restore normal
  behavior.

## Notes for resuming this plan later

- The per-scenario Terraform files needing changes are
  `terraform/scenarios/reference-service/variables.tf`, `service.tf`, and
  `k6.tf`; neither the `ecs-service` nor `ecs-task-oneshot` modules need
  changes (both already support a `containers[*].environment` field).
- `terraform-scenario.yml`'s new `tf-var-overrides` input is intentionally
  generic (not reference-service-specific), so any future scenario can
  reuse the same mechanism for its own one-off variable overrides.
