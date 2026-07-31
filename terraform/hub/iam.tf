# Shared ECS task execution role, used by every scenario's ecs-service /
# ecs-task-oneshot task definitions. Per-scenario task roles are NOT created
# here — each scenario instantiates its own via this same module (empty
# task_roles map keeps this call to just the execution role).
module "task_roles" {
  source = "../modules/iam-task-roles"

  create_execution_role = true
  task_roles            = {}

  tags = var.tags
}
