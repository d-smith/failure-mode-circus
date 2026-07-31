# Failure Mode Circus — Shared Infrastructure Plan

## Context

The goal of this project is to build a library of runnable examples that each demonstrate a specific distributed-systems failure mode (cascading failures, retry storms, timeouts, network partitions, resource exhaustion, etc.) and a mitigation for it. Each example is a small set of containerized services deployed together to mimic a real application, exercised by load/chaos tests that prove the failure occurs and that the mitigation works.

Before building any individual example, this plan builds the **shared infrastructure** every future example will reuse: containerization conventions, an AWS ECS/Fargate deployment target, a CI/CD pipeline (GitHub Actions), and a Grafana k6 test-execution harness. It also builds **one minimal reference service** deployed end-to-end through that pipeline, purely to prove build → push → deploy → test works before investing in a real failure-mode scenario.

Decisions locked in for this pass: Terraform for IaC, GitHub Actions for CI/CD (OIDC, no long-lived AWS keys), k6 running as its own ECS Fargate task (not a service) inside the VPC, reference service written in Go, GitHub repo `d-smith/failure-mode-circus`, AWS region `us-east-1`.

## Architecture: Hub and Spokes

Repo currently doesn't exist yet, not a git repo. Design so many independent scenarios can share plumbing without touching each other's files:

- **Hub** (`terraform/hub/`): always-on shared layer — VPC, ECS cluster, ECR repos, base IAM/OIDC, CloudWatch log groups, Cloud Map namespace. Applied once, left running (near-zero idle cost once NAT is avoided — see below).
- **Spokes** (`terraform/scenarios/<name>/`): one per failure-mode example, including `reference-service` built here. Each has its own Terraform state, own ECS services/tasks/security groups, reads hub outputs via `terraform_remote_state`, and can be `terraform destroy`'d independently without affecting other scenarios or the hub.

Adding scenario #2 later means: new `services/<name>/` folders, new `terraform/scenarios/<name>/` root module (copy reference-service as template), new `k6/scripts/<name>/*.js`, new thin orchestrator workflow calling the same reusable workflows. No shared module or hub resource needs editing — hub's ECR module is `for_each`-driven off a tfvars list so new images are a one-line addition.

## Repo Layout

```
failure-mode-circus/
├── .github/workflows/
│   ├── terraform-hub.yml            # plan (PR) / apply (main) for terraform/hub + modules
│   ├── terraform-scenario.yml       # reusable: plan/apply any scenario root module
│   ├── build-and-push.yml           # reusable: docker build + push to ECR (OIDC)
│   ├── deploy-service.yml           # reusable: register task def + update ECS service
│   ├── run-k6-task.yml              # reusable: ecs run-task, poll, gate on exit code
│   └── scenario-reference-service.yml  # orchestrator chaining the reusable workflows
├── terraform/
│   ├── bootstrap/                   # ONE-TIME manual apply, local state
│   │   ├── main.tf                  # S3 state bucket (versioned, encrypted) + DynamoDB lock table
│   │   └── oidc.tf                  # GitHub OIDC provider (account-global, created once)
│   ├── modules/
│   │   ├── networking/              # VPC, private subnets x2 AZ, VPC interface endpoints, no NAT by default
│   │   ├── ecs-cluster/             # Fargate cluster + Cloud Map/Service Connect namespace
│   │   ├── ecr-repo/                # one ECR repo w/ lifecycle policy per instantiation
│   │   ├── ecs-service/             # generic: list-of-containers, Service Connect config surface
│   │   ├── ecs-task-oneshot/        # generic run-once Fargate task def (used by k6 runner)
│   │   ├── iam-task-roles/          # execution role (shared) + task role (per-scenario)
│   │   ├── github-oidc-role/        # scoped deploy roles assumable via OIDC, per purpose
│   │   └── logging/                 # CloudWatch log group, short retention, naming convention
│   ├── hub/                         # composes networking + ecs-cluster + logging + ecr; stable outputs.tf contract
│   └── scenarios/reference-service/ # first spoke: ecs-service (health API) + ecs-task-oneshot (k6 runner)
├── services/reference-service/      # Go HTTP health-check API + Dockerfile (distroless, static binary)
├── k6/
│   ├── Dockerfile                   # FROM grafana/k6, scripts baked in and versioned with infra
│   └── scripts/reference-service/smoke.js
├── scripts/                         # destroy-all.sh (scenarios first, then hub), plan-all.sh
└── docs/architecture.md             # session lifecycle, cost notes, "adding a new scenario" playbook
```

## Key Design Decisions

- **Service discovery: ECS Service Connect**, not plain Cloud Map. It's built on Cloud Map but adds client-side load balancing, per-service DNS in a namespace, and traffic metrics/timeout controls at the proxy layer — this keeps a path open for future scenarios to inject network-level failures (timeouts, connection limits) via Terraform-managed listener config rather than hand-rolled iptables tricks. Reference service gets DNS name `reference-service.internal`, reachable only from inside the VPC by the k6 task.
- **No load balancer / public ingress** in the shared layer — the system under test only needs to be reachable by the internal k6 task. An ALB module can be added later, opt-in, for a scenario specifically about ingress-layer failures.
- **No NAT Gateway by default** — the single biggest recurring-cost risk (~$32-35/mo fixed + per-GB data processing) for infra that should be idle most of the time. Use VPC Interface Endpoints (ecr.api, ecr.dkr, logs) + S3 Gateway Endpoint (free) instead, so Fargate tasks in fully private subnets can pull images and ship logs with no NAT. A future scenario needing public egress adds NAT as an opt-in flag on its own tfvars, not globally.
- **IAM**: OIDC provider + broad `terraform-apply` role created once in bootstrap/hub; a separate, narrower `build-and-push`/`deploy` role (ECR push + ECS RegisterTaskDefinition/UpdateService only, no IAM/VPC write) for the day-to-day workflow steps. Task execution role is shared across all scenarios (identical permissions everywhere); task role is generated per-scenario (reference service needs ~none; later scenarios needing e.g. SQS access get their own scoped role).
- **k6 packaging**: scripts baked into a custom `k6/Dockerfile` image, not fetched from S3 at runtime — keeps the k6 image version-locked to the exact test that ran, no extra runtime fetch permissions needed. One k6 image serves every scenario; the ECS task-definition command override selects which script to run (`k6 run /scripts/reference-service/smoke.js`).
- **Results/gating**: k6's own exit code (non-zero on threshold failure) is the pipeline's pass/fail signal — `run-k6-task.yml` does `ecs run-task` → `wait tasks-stopped` → `describe-tasks` for exit code → fail the job if non-zero. Console output goes to CloudWatch Logs via the `awslogs` driver, which is sufficient for the smoke test. Defer S3 JSON-summary export (needed later for before/after mitigation comparisons) until the first real scenario needs it.
- **State backend bootstrap**: `terraform/bootstrap/` is a separate root module with local state, applied manually once (`terraform init && apply`) since it creates the very S3 bucket/DynamoDB table the rest of Terraform will use as backend. This is the one piece of Terraform never applied via CI.
- **Hub/scenario coupling**: scenario root modules read hub outputs via `terraform_remote_state` (simplest to start). Treat `terraform/hub/outputs.tf` as a stable contract — only add outputs, never rename/remove — documented in `docs/architecture.md`. Revisit toward SSM Parameter Store outputs (looser coupling) only if this becomes painful after a few real scenarios exist.
- **`ecs-service` module interface**: accept a *list* of container definitions (not a single image/port pair) from day one, even though the reference service only needs one container — avoids a breaking redesign once a scenario needs sidecars or multi-container task groups.

## Execution Approach

The user wants to direct execution task by task: after each task below, stop and show what changed, and get explicit go-ahead before starting the next one. Do not batch multiple tasks together unprompted. Track this list with TaskCreate/TaskUpdate, one task `in_progress` at a time.

Progress tracking: as each task below is completed and confirmed, check it off here (`- [ ]` → `- [x]`) and append a dated entry to `progress.txt` at the repo root summarizing what was done and any notable decisions/deviations.

## Task List

**Repo setup**
- [x] 1.Create `.gitignore` (Terraform state/`.terraform`, Go build artifacts, etc.), create the directory skeleton from the Repo Layout section (empty placeholder files/READMEs where needed).
- [x] 2. Create the GitHub repo `d-smith/failure-mode-circus` (or confirm it already exists) and push the initial scaffold.

**State backend bootstrap**
- [x] 3. Write `terraform/bootstrap/main.tf`: S3 state bucket (versioned, encrypted, public access blocked, TLS-only bucket policy) + DynamoDB lock table.
- [x] 4. Write `terraform/bootstrap/oidc.tf`: GitHub OIDC provider for `token.actions.githubusercontent.com`.
- [x] 5. Manually `terraform init && terraform apply` the bootstrap module (local state) — one-time, not via CI. Record the resulting bucket name/table name/OIDC provider ARN for use in later steps.

**Shared Terraform modules (one task each)**
- [x] 6. `terraform/modules/networking`: VPC, 2 private subnets across AZs, route tables, VPC interface endpoints (ecr.api, ecr.dkr, logs) + S3 gateway endpoint, no NAT by default.
- [x] 7. `terraform/modules/ecs-cluster`: Fargate cluster + Cloud Map/Service Connect namespace.
- [x] 8. `terraform/modules/logging`: CloudWatch log group factory with naming convention and short retention.
- [x] 9. `terraform/modules/iam-task-roles`: shared task execution role + per-scenario task role factory.
- [x] 10. `terraform/modules/github-oidc-role`: scoped IAM roles assumable via the OIDC provider, parameterized by repo/branch/purpose.
- [x] 11. `terraform/modules/ecr-repo`: single ECR repo module with lifecycle policy.
- [x] 12. `terraform/modules/ecs-service`: generic service module accepting a list of container definitions + Service Connect config.
- [x] 13. `terraform/modules/ecs-task-oneshot`: generic run-once Fargate task definition module (used later by the k6 runner).

**Hub**
- [x] 14. Write `terraform/hub/main.tf` + `backend.tf` composing networking + ecs-cluster + logging, backend pointed at the bootstrap S3/DynamoDB.
- [x] 15. Write `terraform/hub/ecr.tf` (ECR repos for `reference-service` and `k6-runner` images, `for_each` over a tfvars list) and `terraform/hub/oidc.tf` (hub-scoped `terraform-apply` and `build-and-push`/`deploy` roles).
- [x] 16. Write `terraform/hub/outputs.tf` (vpc_id, private_subnet_ids, cluster_arn, cloudmap_namespace_id, ecr repo URLs) — treat as a stable contract going forward.
- [x] 17. Manually `terraform init && terraform apply` the hub module the first time; confirm resources in AWS console/CLI.

**Reference service**
- [x] 18. Write the Go health-check service (`services/reference-service/`) + Dockerfile (distroless, static binary); build and run it locally to confirm `/healthz` works before containerizing infra around it.
- [ ] 19. Write `terraform/scenarios/reference-service/`: `main.tf` (remote state data source against hub), `service.tf` (ecs-service instantiation, Service Connect-enabled), `iam.tf` (scenario task role + github-oidc-role instantiation), `backend.tf` (own state key), `variables.tf`/`outputs.tf`/`terraform.tfvars`.
- [ ] 20. Add `k6.tf` to the same scenario module instantiating `ecs-task-oneshot` for the k6 runner task definition (not yet run).
- [ ] 21. Manually `terraform apply` the reference-service scenario the first time; confirm the ECS service reaches steady state with 1 running task.

**k6 harness**
- [ ] 22. Write `k6/Dockerfile` (FROM `grafana/k6`, scripts copied in) and `k6/scripts/reference-service/smoke.js` (few VUs, short duration, hits `reference-service.internal`, asserts status 200 + latency threshold); build and smoke-test the image locally against a local run of the Go service if practical.

**CI/CD workflows (one task each)**
- [ ] 23. `.github/workflows/terraform-scenario.yml` — reusable plan/apply workflow, generic on working-directory input.
- [ ] 24. `.github/workflows/build-and-push.yml` — reusable docker build/push to ECR via OIDC.
- [ ] 25. `.github/workflows/deploy-service.yml` — reusable register-task-def + update-service + wait-for-steady-state.
- [ ] 26. `.github/workflows/run-k6-task.yml` — reusable ecs run-task + poll + exit-code gate.
- [ ] 27. `.github/workflows/terraform-hub.yml` — plan on PR / apply on merge for `terraform/hub` + `terraform/modules`.
- [ ] 28. `.github/workflows/scenario-reference-service.yml` — orchestrator chaining tasks 23-26 for the reference-service scenario specifically.

**End-to-end proof and wrap-up**
- [ ] 29. Open a PR touching the reference-service scenario, confirm plan-only jobs run clean; merge to main and watch apply → build → deploy → k6 run execute; confirm the k6 ECS task exits 0 and the pipeline goes green.
- [ ] 30. Write `scripts/destroy-all.sh` (scenario stacks before hub) and `scripts/plan-all.sh`.
- [ ] 31. Write `docs/architecture.md` (session lifecycle, cost notes, stable-outputs contract, "adding a new scenario" playbook) and `docs/adding-a-new-scenario.md`.
- [ ] 32. Run the teardown verification: `terraform destroy` the reference-service scenario only, confirm hub/VPC/cluster/ECR remain untouched.

## Verification

- `terraform validate` / `terraform plan` clean on bootstrap, hub, and reference-service root modules (checked as each is applied in tasks 5, 17, 21).
- `docker build` succeeds locally for both `services/reference-service` and `k6/` images (tasks 18, 22).
- After task 29's merge, confirm in AWS Console/CLI: ECS service `reference-service` running 1 task in `RUNNING` state with Service Connect enabled; `aws ecs describe-tasks` on the k6 task shows `exitCode: 0`; CloudWatch Logs for both task families show expected output.
- Confirm no NAT Gateway exists in the hub VPC (`aws ec2 describe-nat-gateways`) and that image pulls/log delivery still work via VPC endpoints only.
- Task 32 is the final teardown verification: `terraform destroy` the reference-service scenario only, confirm hub and its VPC/cluster/ECR remain untouched and reference-service resources are fully removed.
