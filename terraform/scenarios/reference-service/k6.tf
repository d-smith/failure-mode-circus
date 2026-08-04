# Task definition only - no aws_ecs_service. Network placement and any
# Service Connect client config are supplied on the `aws ecs run-task`
# invocation itself (see run-k6-task.yml, task 26), not stored here.
module "k6_runner" {
  source = "../../modules/ecs-task-oneshot"

  name_prefix = var.name_prefix

  task_name = "k6-runner"
  vpc_id    = data.terraform_remote_state.hub.outputs.vpc_id

  execution_role_arn = data.terraform_remote_state.hub.outputs.execution_role_arn
  task_role_arn      = module.task_role.task_role_arns["k6-runner"]
  log_group_name     = data.terraform_remote_state.hub.outputs.log_group_names["k6-runner"]

  containers = [
    {
      name    = "k6-runner"
      image   = "${data.terraform_remote_state.hub.outputs.ecr_repository_urls["k6-runner"]}:${var.k6_image_tag}"
      command = ["run", "/scripts/reference-service/smoke.js"]
      # smoke.js's own default targets reference-service.internal (Service
      # Connect), which this standalone RunTask can never resolve - point it
      # at the classic Cloud Map registration from service.tf instead.
      environment = [
        {
          name  = "BASE_URL"
          value = "http://reference-service-direct.internal:8080"
        }
      ]
    }
  ]

  tags = var.tags
}
