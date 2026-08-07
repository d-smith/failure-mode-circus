# Adding a new scenario

Step-by-step playbook for adding a new failure-mode scenario, using
`reference-service` as the template throughout. See `docs/architecture.md`
for the reasoning behind each piece; this doc is just the checklist.

Pick a scenario name (`<name>`) - it becomes the service directory name, the
ECR repo name, the Cloud Map discovery name, and the task-definition family
suffix, so keep it short and consistent everywhere below.

## 1. Extend hub

Hub owns the ECR repos and log groups every scenario draws from, and it's
`for_each`-driven so this is additive, not an edit to existing resources:

- `terraform/hub/terraform.tfvars`: add `<name>` to `ecr_repo_names` (and a
  second entry if the scenario needs its own k6 image variant - usually not,
  since one shared `k6-runner` image serves every scenario).
- `terraform/hub/variables.tf`: add `<name>` to `log_group_names`'s default
  (or override via tfvars) if the service needs its own log group.

Apply hub (`terraform apply` in `terraform/hub/`, or let `terraform-hub.yml`
do it via a PR) before moving on - the new ECR repo needs to exist before you
can push an image to it.

## 2. Write the service

`services/<name>/` - follow `services/reference-service/`'s shape:
minimal Go HTTP service (or whatever language/runtime the scenario calls
for), a two-stage Dockerfile (build stage + distroless runtime), a
`/healthz` endpoint at minimum. Verify locally before wiring any
infrastructure around it: `go build`, run it, `curl /healthz`; `docker
build`, run the container, `curl /healthz` again through it.

## 3. Write the scenario's Terraform root module

`terraform/scenarios/<name>/` - copy `terraform/scenarios/reference-service/`
as a starting point:

- `backend.tf`: own state key, `scenarios/<name>/terraform.tfstate`.
- `main.tf`: provider block + `data "terraform_remote_state" "hub"` reading
  hub's state directly (the one place a scenario couples to hub).
- `iam.tf`: `iam-task-roles` module call with `create_execution_role = false`
  (reuse hub's shared execution role) and a `task_roles` entry for `<name>`
  (plus `k6-runner` if this scenario runs its own k6 task - see step 5).
- `service.tf`: `ecs-service` module instantiation. Point
  `execution_role_arn`, `log_group_name`, and `ecr_repository_urls["<name>"]`
  at hub's remote-state outputs. Decide on Service Connect vs. classic Cloud
  Map discovery per the client - **if a standalone `RunTask` (like a k6 test)
  needs to reach this service, it needs `cloudmap_namespace_id` +
  `service_discovery_name` set too, not just `service_connect_services`** -
  Service Connect's DNS name is invisible to standalone tasks (see
  `docs/architecture.md`'s "Networking" section for why).
- `k6.tf` (if this scenario has its own k6 test): `ecs-task-oneshot` module
  instantiation reusing the shared `k6-runner` image, with a `command`
  override pointing at `/scripts/<name>/*.js` and a `BASE_URL` environment
  override pointing at whichever DNS name step 3's `service.tf` set up for
  standalone-task reachability.
- `outputs.tf`, `variables.tf`, `terraform.tfvars`: mirror
  reference-service's.

Run `terraform init -backend=false` + `terraform validate` locally first
(syntax/composition check, no real backend needed) before the real
`terraform init` against the actual backend.

## 4. Write the k6 script

`k6/scripts/<name>/*.js` - gets baked into the *same* shared `k6/Dockerfile`
image as every other scenario's scripts (no new Dockerfile, no new image).
Target whichever DNS name step 3 wired up as `BASE_URL`, with a `BASE_URL`
env var override so it's still runnable locally against a local instance of
the service. See `README.md`'s "Running the k6 smoke test locally" section
for the local dev-loop commands.

## 5. First manual apply

`terraform plan` + `terraform apply` in `terraform/scenarios/<name>/`. Expect
the ECS service to fail to reach steady state at first - there's no image in
the new ECR repo yet, since no CI workflow has built/pushed one. Manually
`docker build` / tag / push the initial image to unblock it (same sequence
`reference-service` went through in tasks 19-21), then confirm the service
reaches steady state.

## 6. Write the orchestrator workflow

`.github/workflows/scenario-<name>.yml` - copy
`scenario-reference-service.yml` and adjust: path filters (`terraform/
scenarios/<name>/**`, `services/<name>/**`, plus `k6/scripts/<name>/**` if
distinct from `k6/**`), the ECR repository names passed to `build-and-push.yml`,
the task-definition family / container / service names passed to
`deploy-service.yml`, and the task-definition family passed to
`run-k6-task.yml`. No changes needed to any of the four reusable workflow
files themselves - that's the point of them being generic.

## 7. Prove it end-to-end

Open a PR touching the new scenario's files. Confirm only the plan-only
`terraform` job runs (everything else should show as skipped). Merge, and
watch `terraform` (apply) -> build -> deploy -> k6 run execute in sequence.
Check the k6 task's actual output via CloudWatch Logs
(`aws logs tail /ecs/failure-mode-circus/k6-runner --since 1h`) to confirm a
clean pass, not just a green Actions checkmark - a DNS or permissions
problem can still show up as a real k6 failure even if every workflow step
itself succeeds (this happened during `reference-service`'s own first
end-to-end run; see `progress.txt`, tasks 29-30, for the full diagnosis).

If the scenario's `containers` entries set `health_check` (see the
`ecs-service` module), also confirm ECS's own verdict on the running
task, separate from k6's pass/fail:

```
TASK_ARN=$(aws ecs list-tasks --cluster failure-mode-circus-cluster \
  --service-name <name> --query 'taskArns[0]' --output text)

aws ecs describe-tasks --cluster failure-mode-circus-cluster \
  --tasks "$TASK_ARN" \
  --query 'tasks[0].{status:lastStatus,health:healthStatus}'
```

Expect `healthStatus: HEALTHY` once the configured `start_period` and a
couple of `interval`s have elapsed (`UNKNOWN` briefly right after a fresh
deploy is normal). This is what actually gates whether ECS considers a
task healthy - k6 checks prove the API behaves correctly, this proves ECS
itself agrees the container is alive (`reference-service`'s `/calc` +
`healthcheck` self-check subcommand, added after the baseline plan, is the
first scenario to use this).
