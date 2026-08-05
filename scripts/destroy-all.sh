#!/usr/bin/env bash
# Tears down every scenario stack, then hub - in that order, since scenarios
# depend on hub's networking/logging/ECR (no NAT Gateway, so a scenario's
# Fargate tasks need hub's VPC endpoints to even pull images/ship logs while
# being destroyed). Never touches terraform/bootstrap: that's the one root
# module that stays local and manual (task 5) - it holds the S3 state
# bucket/DynamoDB lock table every other root module's backend depends on,
# so destroying it here would be catastrophic, not a convenience.
#
# By default each `terraform destroy` still shows its plan and prompts for
# confirmation (Terraform's own safety net). Pass -y/--auto-approve to skip
# the prompts for unattended use.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

AUTO_APPROVE=()
if [[ "${1:-}" == "-y" || "${1:-}" == "--auto-approve" ]]; then
  AUTO_APPROVE=(-auto-approve)
fi

for scenario_dir in "$REPO_ROOT"/terraform/scenarios/*/; do
  scenario_name="$(basename "$scenario_dir")"
  echo "==> Destroying scenario: $scenario_name"
  terraform -chdir="$scenario_dir" init -input=false
  terraform -chdir="$scenario_dir" destroy "${AUTO_APPROVE[@]}"
done

echo "==> Destroying hub"
terraform -chdir="$REPO_ROOT/terraform/hub" init -input=false
terraform -chdir="$REPO_ROOT/terraform/hub" destroy "${AUTO_APPROVE[@]}"

echo "==> Done. terraform/bootstrap was intentionally left untouched."
