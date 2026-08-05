# Architecture

`failure-mode-circus` is a library of runnable examples that each demonstrate
a specific distributed-systems failure mode and a mitigation for it, deployed
to AWS ECS/Fargate and exercised by Grafana k6 load/chaos tests. This
document covers how the pieces fit together; see `baseline-plan.md` for the
original build plan and `progress.txt` for the task-by-task history of how it
was actually built (including bugs hit and how they were diagnosed).

## Layers

```
terraform/bootstrap/    local, manual, applied once - state backend + OIDC provider
terraform/hub/          always-on shared infra - applied via CI (terraform-hub.yml)
terraform/scenarios/*/  one stack per failure-mode scenario - applied via its own workflow
terraform/modules/*/    shared building blocks composed by hub and scenarios
services/*/             one Go service per scenario
k6/                     one shared k6 image; scripts/<scenario>/*.js baked in per scenario
.github/workflows/      reusable CI building blocks + per-scenario/hub orchestrators
scripts/                local convenience wrappers (plan-all.sh, destroy-all.sh)
```

**`bootstrap`** creates the S3 state bucket, DynamoDB lock table, and the
GitHub Actions OIDC provider. It's the one root module that stays local and
manual (`terraform.tfstate` is gitignored) - every other root module's
backend depends on what it creates, so there's no way to bootstrap it via the
CI that depends on it existing first.

**`hub`** is the always-on shared layer: VPC (no NAT Gateway - see
"Networking" below), ECS cluster + Cloud Map namespace, CloudWatch log
groups, ECR repos, the shared ECS task execution role, and the two
OIDC-trusted IAM roles every workflow assumes. Applied once manually the
first time (task 17), then via `terraform-hub.yml` on every PR/merge that
touches `terraform/hub/**` or `terraform/modules/**` (a shared-module change
can affect hub even if no hub file itself changed).

**Scenarios** (currently just `reference-service`) are independent stacks:
their own state key, their own `terraform_remote_state` read of hub's
outputs, their own task role(s), their own CI workflow. Destroying one never
touches hub or any other scenario. See "Adding a new scenario" below and
`docs/adding-a-new-scenario.md` for the full playbook.

## Session lifecycle / cost management

Hub's VPC interface endpoints (ecr.api, ecr.dkr, logs) are the dominant
recurring cost (~$43.80/mo), not the Fargate tasks themselves (~$9/mo for
reference-service running 24/7). Because there's no NAT Gateway, a running
scenario's tasks depend on those endpoints for image pulls and log shipping
- so teardown order matters:

1. Destroy scenario stack(s) first (`terraform destroy` in each
   `terraform/scenarios/*/`, or `scripts/destroy-all.sh`, which does this
   automatically in the right order).
2. Then remove hub's interface endpoints
   (`terraform destroy -target=module.networking.aws_vpc_endpoint.interface`
   in `terraform/hub/`) - or destroy hub entirely if you want the VPC/ECS
   cluster/ECR gone too.

`terraform/bootstrap` is never part of this teardown - it holds the state
backend everything else depends on.

To resume: `terraform apply` in `terraform/hub/` (no target - recreates
whatever was removed), then `terraform apply` in each scenario (no rebuild/
repush needed; the same images are still sitting in ECR). See the README's
"Cost management / pausing work" section for the numbers and full walkthrough
- this section is the architectural reasoning behind it.

Adding classic Cloud Map service discovery (see "Networking" below) added no
meaningful cost: no new namespace, no per-instance fee, and negligible DNS
query volume at this project's scale.

## Stable-outputs contract

`terraform/hub/outputs.tf` is the interface every scenario reads via
`data "terraform_remote_state" "hub"` instead of reaching into hub's state
directly. The file's own header states the rule: **only add outputs, never
rename or remove one** - a scenario module years from now should be able to
read an output added on day one without hub ever having broken it. Current
contract (11 outputs):

| Output | Used for |
|---|---|
| `vpc_id`, `vpc_cidr_block` | Scenario security group placement/ingress scoping |
| `private_subnet_ids` | Where scenario Fargate tasks run |
| `cluster_arn` | Which ECS cluster scenario services/tasks register into |
| `cloudmap_namespace_id` | Service Connect + classic Cloud Map registration |
| `ecr_repository_urls` | Map of logical image name -> repo URL, for task definitions and CI build/push |
| `execution_role_arn` | Shared ECS task execution role (identical across all scenarios) |
| `log_group_names`, `log_group_arns` | Map of logical name -> CloudWatch log group, for task definitions |
| `oidc_terraform_apply_role_arn` | `terraform-scenario.yml`'s default `role-to-assume` |
| `oidc_build_and_push_role_arn` | `build-and-push.yml`/`deploy-service.yml`/`run-k6-task.yml`'s default `role-to-assume` |

## Networking and service discovery

No NAT Gateway by default - the single biggest avoidable recurring cost for
infra that's idle most of the time. Fargate tasks in fully private subnets
reach ECR and CloudWatch Logs via VPC interface endpoints, and S3 via the
free gateway endpoint, so they never need public egress at all.

Two independent, coexisting DNS mechanisms exist for reaching a service,
because they solve different problems:

- **ECS Service Connect** (`reference-service.internal`): the default for
  any client that's itself part of an ECS service or that Service Connect
  otherwise enrolls. Resolution works *only* through the Envoy sidecar proxy
  ECS injects into Service-Connect-configured tasks - it is not a plain
  VPC-wide-resolvable DNS record.
- **Classic AWS Cloud Map service discovery**
  (`reference-service-direct.internal`): a real Route 53 private-hosted-zone
  `A` record, resolvable by *any* resource in the VPC. This exists
  specifically because `ecs run-task` (standalone tasks, used for the
  k6-runner oneshot task - see below) has no `serviceConnectConfiguration`
  parameter, so a standalone task can never resolve a Service Connect name.
  This was discovered the hard way: a live k6 task run failed 100% of
  requests with a DNS lookup error before this was added (see `progress.txt`,
  tasks 29-30).

**Rule of thumb when wiring a new client to a service:** if the client is a
long-running ECS *service*, Service Connect's name works fine. If the client
is a standalone `RunTask` invocation (a one-shot job, a k6 test, anything
without an `aws_ecs_service`), it needs the classic Cloud Map name instead -
Service Connect's DNS is invisible to it.

## k6 packaging

One `k6/Dockerfile` (`grafana/k6:2.1.0`) serves every scenario - scripts are
baked in at `/scripts/<scenario>/*.js`, not fetched from S3 at runtime, so
the image is version-locked to the exact test that ran and no extra runtime
fetch permissions are needed. Each scenario's `k6.tf` selects its own script
via the task definition's `command` override
(`["run", "/scripts/reference-service/smoke.js"]`); network placement and any
environment overrides (like `BASE_URL`, pointed at the classic Cloud Map
name) are supplied on the `run-task` invocation and task definition, not
baked into the shared image.

## CI/CD pipeline

Six workflow files, split into reusable building blocks and thin,
directly-triggered orchestrators:

**Reusable** (`workflow_call` only, never triggered directly):
- `terraform-scenario.yml` - plan always; apply only when the caller says so. Two jobs (`Plan`, `Apply`) so the exact reviewed plan is what gets applied, not a re-plan.
- `build-and-push.yml` - docker build, tag `:latest` + `:<git-sha>`, push both.
- `deploy-service.yml` - describe the live task def, swap one container's image, register a new revision, update the service, wait for steady state. Never redefines the task's shape (cpu/memory/networking) - Terraform owns that.
- `run-k6-task.yml` - `run-task`, poll until stopped, gate the job on the container's exit code.

**Directly triggered:**
- `terraform-hub.yml` - plan on PR, apply on merge, for `terraform/hub/**` and `terraform/modules/**`.
- `scenario-reference-service.yml` - the orchestrator: plan on PR (nothing else runs); on merge, `terraform` (apply) -> `build-reference-service` + `build-k6-runner` (parallel) -> `deploy-reference-service` -> `run-k6-smoke-test`, in that dependency order.

Both directly-triggered workflows use a **hardcoded default role ARN** per
purpose (`role-to-assume` inputs default to the known
`failure-mode-circus-terraform-apply` / `failure-mode-circus-build-and-push`
role ARNs) rather than looking them up dynamically - a workflow can't do a
Terraform data lookup before a role is assumed, the same reason
`backend.tf` files hardcode the state bucket/table. Two OIDC roles, scoped by
purpose: `terraform-apply` is broad-but-scoped (can manage this project's
VPC/ECS/IAM/ECR/logs resources, nothing outside that); `build-and-push`
is narrow (ECR push + ECS deploy/run-task actions only, no IAM or VPC write).

The OIDC trust policies use GitHub's **immutable-ID subject-claim format**
(`repo:owner@ownerId/repo@repoId:...`) rather than the plain `owner/repo`
form - GitHub switches to this once an account or repo has ever been
renamed, and the plain form will fail `AssumeRoleWithWebIdentity` silently
if that's happened. If OIDC ever starts failing again, check a live token's
actual `sub` claim (CloudTrail's `AssumeRoleWithWebIdentity` events show it)
before assuming the trust policy is wrong.

## Adding a new scenario

Briefly: new `services/<name>/`, new `terraform/scenarios/<name>/` (copy
`reference-service` as a template), new `k6/scripts/<name>/*.js`, one line
added to hub's `ecr_repo_names`/`log_group_names`, one new orchestrator
workflow copied from `scenario-reference-service.yml`. No shared module or
existing hub resource needs editing. Full step-by-step:
`docs/adding-a-new-scenario.md`.
