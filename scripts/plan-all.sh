#!/usr/bin/env bash
# Runs `terraform plan` across hub and every scenario stack, so you can
# check the whole repo for drift in one shot instead of cd-ing into each
# root module by hand. terraform/bootstrap is deliberately excluded - it
# keeps its state local (task 5), so a plan against it only works correctly
# on the one machine that originally applied it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Planning hub"
terraform -chdir="$REPO_ROOT/terraform/hub" init -input=false
terraform -chdir="$REPO_ROOT/terraform/hub" plan

for scenario_dir in "$REPO_ROOT"/terraform/scenarios/*/; do
  scenario_name="$(basename "$scenario_dir")"
  echo "==> Planning scenario: $scenario_name"
  terraform -chdir="$scenario_dir" init -input=false
  terraform -chdir="$scenario_dir" plan
done

echo "==> All plans complete."
