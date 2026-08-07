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
- Local AWS credentials configured (`aws configure`, environment variables, or an SSO profile set up via IAM Identity Center) with permissions sufficient for the one-time manual applies of `terraform/bootstrap` and `terraform/hub`.
- A GitHub account with rights to create/push to `d-smith/failure-mode-circus`.

## Running the k6 smoke test locally

`k6/scripts/reference-service/smoke.js` targets `reference-service.internal:8080`
(the Service Connect DNS name) by default, but reads a `BASE_URL` env var so it
can also run against a local instance of the Go service.

### Recommended: fully containerized (matches the exact image pushed to ECR)

`k6/Dockerfile` is pinned to `grafana/k6:2.1.0`. Building and running it
locally exercises the exact image that gets pushed to ECR and run in ECS,
rather than whatever k6 version happens to be installed on your machine.

1. Build both images:
   ```
   docker build -t fmc-reference-service:local ./services/reference-service
   docker build -t fmc-k6:local ./k6
   ```
2. Put them on a shared Docker network and start the service on it - k6 will
   reach it by container name, mirroring how Service Connect resolves
   `reference-service.internal` in ECS:
   ```
   docker network create fmc-smoke-test
   docker run -d --name reference-service-smoke --network fmc-smoke-test fmc-reference-service:local
   ```
3. Run the smoke test against it:
   ```
   docker run --rm --network fmc-smoke-test \
     -e BASE_URL=http://reference-service-smoke:8080 \
     fmc-k6:local run /scripts/reference-service/smoke.js
   ```
   A passing run ends with a green `THRESHOLDS` block (`checks` rate 100%,
   `http_req_duration p(95)<500`) and exits 0 - k6 exits non-zero if a check or
   threshold fails, which is what the future `run-k6-task.yml` (task 26) exit-code
   gate relies on.
4. Clean up:
   ```
   docker rm -f reference-service-smoke
   docker network rm fmc-smoke-test
   docker rmi fmc-k6:local fmc-reference-service:local
   ```

(`docker run --network host` / `host.docker.internal` may seem like a
shorter path to reach a locally-running Go binary instead of a containerized
one, but don't rely on it - it doesn't work on every Docker setup. The
container-to-container network above is the portable option.)

### Quicker iteration: native k6 CLI

Faster if you're actively editing the script itself and don't want a Docker
build in the loop - but note `go install go.k6.io/k6@latest` currently
resolves to k6 v1.8.0, not the Dockerfile's pinned 2.1.0, so treat this as a
quick sanity check rather than a substitute for the containerized run above.

1. Build and run the service in the background:
   ```
   cd services/reference-service
   go build -o /tmp/reference-service .
   LISTEN_ADDR=:8080 /tmp/reference-service &
   ```
2. Confirm it's up: `curl http://localhost:8080/healthz` should return `ok`.
3. Run the smoke test against it:
   ```
   BASE_URL=http://localhost:8080 k6 run k6/scripts/reference-service/smoke.js
   ```
4. Stop the local service when done: `kill %1` (or find/kill the PID from
   `ps aux | grep reference-service`).

Don't have the `k6` CLI installed? `go install go.k6.io/k6@latest` builds a
working binary into `$(go env GOPATH)/bin` with no root/package manager needed.

## Cost management / pausing work

Rough standing run rate once the hub and reference-service scenario are both
applied (verified against current AWS pricing, us-east-1):

| Item | Cost |
|---|---|
| 3 VPC interface endpoints (ecr.api, ecr.dkr, logs) x 2 AZs, $0.01/hr each | ~$43.80/mo |
| reference-service Fargate task (0.25 vCPU / 0.5 GB, running 24/7) | ~$9.00/mo |
| ECR storage, CloudWatch Logs, Cloud Map namespace | ~$1-2/mo |
| **Total** | **~$53-55/mo (~$1.80/day)** |

The VPC interface endpoints, not the Fargate task, are the dominant cost, and
they live in the hub - so tearing down a scenario alone only saves the
Fargate portion.

For a short break, leaving everything running is fine - the cost is
negligible. For a longer pause, tear down in this order (the running
reference-service task depends on the interface endpoints for image
pulls/log shipping, since there's no NAT Gateway, so stop it first):

1. `terraform/scenarios/reference-service/`: `terraform destroy` - stops the
   Fargate task (~$9/mo saved).
2. `terraform/hub/`: `terraform destroy -target=module.networking.aws_vpc_endpoint.interface`
   - removes the 3 interface endpoints (~$43.80/mo saved). Leaves the VPC,
   subnets, ECS cluster, ECR repos + pushed images, log groups, and IAM
   roles all intact. Nothing else in hub's config changes, so this is a
   clean, reversible destroy - a later plain `terraform apply` (no
   `-target`) recreates the endpoints exactly as they were.

To resume:

1. `terraform/hub/`: `terraform apply` (no target) - recreates the 3
   endpoints.
2. `terraform/scenarios/reference-service/`: `terraform apply` - recreates
   the Fargate task, pulling the same image already in ECR (no
   rebuild/repush needed).

## Appendix: GitHub Actions OIDC / AWS references

Background reading for the OIDC trust setup in `terraform/bootstrap/oidc.tf` and the
per-purpose roles it will support (`terraform/modules/github-oidc-role/`).

**Official docs**
- [GitHub Docs — Configuring OpenID Connect in Amazon Web Services](https://docs.github.com/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services) — canonical walkthrough: workflow `id-token: write` permission, trusting GitHub's provider in AWS, and scoping the IAM trust policy on the `sub` claim (repo/branch).
- [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials) — the official GitHub Action that exchanges the OIDC token for temporary AWS credentials via `sts:AssumeRoleWithWebIdentity`.

**Terraform-specific**
- [Cloud Posse — How GitHub OIDC Works with AWS](https://docs.cloudposse.com/layers/github-actions/github-oidc-with-aws/) — conceptual diagram of the token flow, mapped to Terraform resources.
- [Xebia — Deploy Terraform to AWS with GitHub Actions using OIDC](https://xebia.com/blog/how-to-deploy-terraform-to-aws-with-github-actions-authenticated-with-openid-connect/) — closest match to this repo's use case (Terraform apply via an OIDC-assumed role).
- [Colin Barker — GitHub Actions and OIDC Update for Terraform and AWS (2025)](https://colinbarker.me.uk/blog/2025-01-12-github-actions-oidc-update/) — explains why AWS now validates against its trusted CA store rather than strictly matching the thumbprint, relevant to the thumbprint comment in `oidc.tf`.

**On scoping the trust policy** (relevant to the future `github-oidc-role` module)
- Condition the role trust policy on `token.actions.githubusercontent.com:sub` (e.g. `repo:d-smith/failure-mode-circus:ref:refs/heads/main`) so only specific repo/branch workflows can assume the role — see the GitHub doc above.
