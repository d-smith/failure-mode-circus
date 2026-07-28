# failure-mode-circus

A library of runnable examples that each demonstrate a specific distributed-systems
failure mode and a mitigation for it, deployed to AWS ECS/Fargate and exercised by
Grafana k6 load/chaos tests. See `baseline-plan.md` for the shared-infrastructure
build plan and `progress.txt` for what's been done so far.

## Required tooling

| Tool | Version | Why it's needed | Install |
|---|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.5 | Everything under `terraform/` (bootstrap, hub, per-scenario modules) is authored against this. Bootstrap, hub, and the reference-service scenario are applied manually from a local machine the first time. | https://developer.hashicorp.com/terraform/install |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | v2 | Configuring local AWS credentials for `terraform apply`, and verifying deployed resources (`aws ecs describe-tasks`, `aws ec2 describe-nat-gateways`, etc.). | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |
| [Docker](https://docs.docker.com/get-docker/) | recent | Building/running the reference-service image (`services/reference-service/Dockerfile`) and the k6 runner image (`k6/Dockerfile`) locally before they're pushed to ECR. | https://docs.docker.com/get-docker/ |
| [Go](https://go.dev/doc/install) | latest stable (currently 1.26.x) | Writing, building, and running the reference service locally before containerizing it. Go only patches the latest two major releases, so track current rather than pinning a version here. | https://go.dev/doc/install |
| [GitHub CLI (`gh`)](https://cli.github.com/) | recent | Creating/verifying the GitHub repo and, later, opening the end-to-end proof PR. Requires `gh auth login` once. | https://cli.github.com/ |
| [git](https://git-scm.com/downloads) | recent | Standard version control. | https://git-scm.com/downloads |

## Recommended (optional) tooling

| Tool | Why it's useful | Install |
|---|---|---|
| [jq](https://jqlang.org/download/) | Parsing `aws ecs describe-tasks` JSON output by hand, e.g. to check a k6 task's exit code. | https://jqlang.org/download/ |
| [k6](https://grafana.com/docs/k6/latest/set-up/install-k6/) | Scripts are baked into a Docker image (`k6/Dockerfile`) rather than requiring a local binary, so this is optional — but it makes iterating on `k6/scripts/*.js` faster (`k6 run` directly instead of a Docker build each time). | https://grafana.com/docs/k6/latest/set-up/install-k6/ |

## Non-software prerequisites

- An AWS account in which to create the `us-east-1` resources described in `baseline-plan.md`.
- Local AWS credentials configured (`aws configure`, environment variables, or an SSO profile) with permissions sufficient for the one-time manual applies of `terraform/bootstrap` and `terraform/hub`.
- A GitHub account with rights to create/push to `d-smith/failure-mode-circus`.
