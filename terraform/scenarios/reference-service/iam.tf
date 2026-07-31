# Per-scenario task roles only - the shared execution role is created once,
# in the hub (terraform/hub/iam.tf), and referenced via remote state below.
# Neither reference-service nor the k6 runner needs AWS permissions of its
# own (~none, per the baseline plan), so managed_policy_arns is left empty
# for both.
module "task_role" {
  source = "../../modules/iam-task-roles"

  create_execution_role = false
  task_roles = {
    reference-service = {
      managed_policy_arns = []
    }
    k6-runner = {
      managed_policy_arns = []
    }
  }

  tags = var.tags
}
