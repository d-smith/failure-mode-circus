module "reference_service" {
  source = "../../modules/ecs-service"

  name_prefix = var.name_prefix

  service_name = "reference-service"
  vpc_id       = data.terraform_remote_state.hub.outputs.vpc_id
  vpc_cidr     = data.terraform_remote_state.hub.outputs.vpc_cidr_block
  subnet_ids   = data.terraform_remote_state.hub.outputs.private_subnet_ids
  cluster_arn  = data.terraform_remote_state.hub.outputs.cluster_arn

  execution_role_arn = data.terraform_remote_state.hub.outputs.execution_role_arn
  task_role_arn       = module.task_role.task_role_arns["reference-service"]
  log_group_name      = data.terraform_remote_state.hub.outputs.log_group_names["reference-service"]

  containers = [
    {
      name      = "reference-service"
      image     = "${data.terraform_remote_state.hub.outputs.ecr_repository_urls["reference-service"]}:${var.image_tag}"
      essential = true
      port_mappings = [
        {
          container_port = var.container_port
          name           = "http"
        }
      ]
    }
  ]

  desired_count = var.desired_count

  # DNS name reference-service.internal, matching the plan's Service Connect
  # design decision.
  enable_service_connect = true
  service_connect_services = [
    {
      port_name      = "http"
      discovery_name = "reference-service"
    }
  ]

  tags = var.tags
}
