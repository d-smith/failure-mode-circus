# reference-service: container health check + `/calc` endpoint

## Context

`reference-service` currently has exactly one endpoint (`/healthz`) and
nothing in AWS ever checks it — no ECS container-level `healthCheck`, no
load balancer. This was found while investigating how health checks work
for `reference-service`: the answer was "they don't, at all." ECS considers
a task healthy purely because its process is running, regardless of
whether it's actually serving correctly.

This plan closes that gap and gives the service something more interesting
than a static `ok` to actually exercise:

1. Wire `/healthz` up as a real **ECS container-level health check**, so
   ECS itself asserts container health for the first time in this project.
2. Add a `/calc` endpoint: takes `op1`, `op2`, and `operator`
   (`add`/`sub`/`mul`/`div`), applies `op1 operator op2`, and returns the
   result. Division by zero is handled explicitly and returns `400`, not a
   crash.
3. Update the k6 smoke test to call `/calc` with randomized operands/
   operator per iteration, treating the expected `400` on division-by-zero
   as a *correct* outcome, not a failure.

This is scoped purely to `reference-service`. It is unrelated to an
earlier, separate discussion in this project about AWS FIS / fault-toggle
scenarios — that idea was set aside as too complex/costly and is not part
of this plan.

We're executing this **step by step, checking off each box as we go**,
verifying before moving to the next. If resuming this plan in a later
session: check which boxes are already checked, read `progress.txt` for
any notes logged along the way, and pick up at the first unchecked step.

## Design decisions (locked in, don't re-litigate on resume)

- **Distroless constraint**: `reference-service`'s runtime image
  (`gcr.io/distroless/static-debian12`, see `services/reference-service/Dockerfile`)
  has no shell, no curl, no wget. A standard `CMD-SHELL curl -f .../healthz`
  health check is impossible here. Instead, the binary gets a self-check
  mode: `./reference-service healthcheck` does an in-process HTTP GET to
  its own `/healthz` and exits 0/1. ECS's `command` then uses the `CMD`
  form (execs directly, no shell needed):
  `["CMD", "/reference-service", "healthcheck"]`. Staying distroless is a
  deliberate existing choice — do not change the base image to add a
  shell/curl instead.
- **`/calc` is `GET` with query params** (`op1`, `op2`, `operator`) —
  consistent with `/healthz`'s style, trivially curlable, no new
  dependencies (stdlib only — `go.mod` has none today).
- **Operands are `float64`**, not int — division won't always produce a
  whole number.
- **k6 keeps only the `/calc` check**, dropping the old `/healthz` check —
  ECS now owns liveness checking, and every `/calc` call already proves the
  service is up, so a redundant `/healthz` check just dilutes the `checks`
  metric.

## Steps

- [x] **1. `services/reference-service/main.go` — `/calc` handler.**
  `calcHandler(w, r)`: reject non-`GET` with `405`. Parse `op1`, `op2` via
  `strconv.ParseFloat` → `400 {"error":"op1 and op2 must be numeric"}` on
  failure. Switch on `operator`: `add`, `sub`, `mul`, `div`; unknown value
  → `400 {"error":"operator must be one of add, sub, mul, div"}`. For
  `div`, explicitly check `op2 == 0` *before* dividing → `400
  {"error":"division by zero"}`. Success → `200` JSON
  `{"op1":...,"op2":...,"operator":...,"result":...}`. Register the route
  in `main()`'s mux alongside `/healthz`.

- [x] **2. `services/reference-service/main.go` — `healthcheck` self-check
  mode.** `runHealthcheck(addr string) int`: derive the port from `addr`
  (the same value `LISTEN_ADDR` already resolves to) via
  `net.SplitHostPort` (fallback `8080`), GET
  `http://127.0.0.1:<port>/healthz` with a 2s-timeout `http.Client`, return
  `1` on error/non-200, else `0`. Returns an int rather than calling
  `os.Exit` directly so it's unit-testable. In `main()`, before starting
  the server: if `os.Args[1] == "healthcheck"`, call
  `os.Exit(runHealthcheck(addr))` and return.

- [x] **3. `services/reference-service/main_test.go` — tests.**
  Table-driven `TestCalcHandler`: add/sub/mul/div success (assert response
  JSON fields), unknown operator (400), non-numeric op1/op2 (400), missing
  params (400), non-GET method (405), division by zero (400, body mentions
  "division by zero"). Follows the existing direct-handler-call pattern
  (`httptest.NewRequest` / `httptest.NewRecorder`). Plus
  `TestRunHealthcheckSuccess` (spin `httptest.NewServer` wrapping the real
  mux, expect 0) and `TestRunHealthcheckFailure` (point at a closed/unused
  address, expect 1). Run `go test ./...` in `services/reference-service`
  and confirm all pass before moving on.

- [x] **4. `services/reference-service/README.md` — docs.** New
  `## Endpoints` section documenting `GET /calc?op1=&op2=&operator=` with
  example success and error responses (bad operator, bad operands,
  division by zero). New `## Health check` section: `./reference-service
  healthcheck` exits 0/1; ECS invokes it via `["CMD", "/reference-service",
  "healthcheck"]` since the runtime image has no shell.

- [x] **5. Local verification before touching Terraform.**
  `go build -o reference-service . && ./reference-service`, then in
  another terminal:
  - `curl "localhost:8080/calc?op1=2&op2=3&operator=sub"` → `200`,
    `result: -1`.
  - `curl "localhost:8080/calc?op1=25&op2=5&operator=div"` → `200`,
    `result: 5`.
  - `curl "localhost:8080/calc?op1=1&op2=0&operator=div"` → `400`,
    `division by zero`.
  - `curl "localhost:8080/calc?op1=1&op2=2&operator=xyz"` → `400`.
  - `./reference-service healthcheck; echo $?` while the server is running
    → `0`; stop the server and re-run → `1`.
  Then Docker: `docker build`, run the container, repeat via `docker exec
  <container> /reference-service healthcheck; echo $?` to confirm it works
  inside the actual distroless runtime image (not just the host).

- [ ] **6. `terraform/modules/ecs-service/variables.tf` — `health_check`
  input.** Add an optional `health_check` field to the `containers` object
  type (same `optional(...)` style already used for `command`, `cpu`,
  etc.):
  ```hcl
  health_check = optional(object({
    command      = list(string)
    interval     = optional(number, 15)
    timeout      = optional(number, 5)
    retries      = optional(number, 3)
    start_period = optional(number, 10)
  }), null)
  ```
  Defaults (15s interval / 5s timeout / 3 retries / 10s start period) put
  the first health verdict ~25-35s after task start and unhealthy
  detection within ~45-60s — fast enough to watch live in a demo, slow
  enough not to flap.

- [ ] **7. `terraform/modules/ecs-service/main.tf` — wire it into the
  container definition.** In the `container_definitions` local, add
  (following the existing null-passthrough precedent already used for
  `cpu`/`command`/etc.):
  ```hcl
  healthCheck = c.health_check == null ? null : {
    command     = c.health_check.command
    interval    = c.health_check.interval
    timeout     = c.health_check.timeout
    retries     = c.health_check.retries
    startPeriod = c.health_check.start_period
  }
  ```

- [ ] **8. `terraform/scenarios/reference-service/service.tf` — turn it on
  for reference-service.** On the `reference-service` container entry,
  add:
  ```hcl
  health_check = {
    command = ["CMD", "/reference-service", "healthcheck"]
  }
  ```
  (module defaults used for interval/timeout/retries/start_period).

- [ ] **9. `k6/scripts/reference-service/smoke.js` — randomized `/calc`
  calls.** Rewrite the iteration body: pick `op1`/`op2` as random integers
  0-20 (naturally includes 0 sometimes, so division-by-zero gets exercised
  without special-casing it) and `operator` randomly from
  `['add','sub','mul','div']`. GET `/calc?op1=&op2=&operator=`. Branch the
  assertion:
  - if `operator === 'div' && op2 === 0`: `check()` only `status === 400`.
  - otherwise: compute the expected result client-side and `check()` both
    `status === 200` and `Math.abs(body.result - expected) < 1e-9`.
  This keeps the `checks rate>0.99` threshold meaningful — an expected
  `400` on division-by-zero passes its own check rather than counting as a
  failure. Drop the old `/healthz`-based check block entirely.

- [ ] **10. `terraform plan` review.** Run `terraform plan` in
  `terraform/scenarios/reference-service` (user runs this, per standing
  preference — Claude gives the command and explains what to expect, does
  not execute). Expect an additive task-definition revision (new
  `healthCheck` block), no destroy/replace of the running service.

- [ ] **11. Ship it through the normal pipeline.** Commit, push, open a PR
  (user handles all git operations). Merging triggers the existing CI/CD
  pipeline (`scenario-reference-service.yml`): terraform apply → build +
  push both images → deploy → run the updated k6 smoke test. This is the
  same proven pipeline the baseline reference-service went through — no
  new workflow changes needed.

- [ ] **12. Live verification after deploy.**
  - `aws ecs describe-tasks` on the running reference-service task —
    confirm `healthStatus` reports `HEALTHY` once the start period elapses.
  - Check the k6 smoke-test run's logs/exit code — confirm `checks` and
    `http_req_duration` thresholds pass, including iterations that hit the
    division-by-zero branch (spot-check a log line showing a `400` on
    `operator=div`).

## Notes for resuming this plan later

- No AWS resources for this feature exist yet as of writing this plan —
  everything is code/Terraform changes not yet applied.
- Hub's VPC interface endpoints were torn down at the end of the previous
  session (per the user), so before step 10/11 can actually run against
  live infra, confirm hub is applied (`terraform apply` with no target in
  `terraform/hub/`) first.
- The `containers` variable's object type and the `container_definitions`
  local are both in `terraform/modules/ecs-service/`; `service.tf` under
  `terraform/scenarios/reference-service/` is the only per-scenario file
  that needs a change to turn the health check on.
