module "reference_service" {
  source = "../../modules/ecs-service"

  name_prefix = var.name_prefix

  service_name = "reference-service"
  vpc_id       = data.terraform_remote_state.hub.outputs.vpc_id
  vpc_cidr     = data.terraform_remote_state.hub.outputs.vpc_cidr_block
  subnet_ids   = data.terraform_remote_state.hub.outputs.private_subnet_ids
  cluster_arn  = data.terraform_remote_state.hub.outputs.cluster_arn

  execution_role_arn = data.terraform_remote_state.hub.outputs.execution_role_arn
  task_role_arn      = module.task_role.task_role_arns["reference-service"]
  log_group_name     = data.terraform_remote_state.hub.outputs.log_group_names["reference-service"]

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
      health_check = {
        command = ["CMD", "/reference-service", "healthcheck"]
      }
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

  # Classic Cloud Map registration alongside Service Connect above - gives
  # reference-service-direct.internal, a plain DNS A record any VPC resource
  # can resolve (the k6-runner RunTask can't use Service Connect's DNS at
  # all; see the ecs-service module's cloudmap_namespace_id description).
  cloudmap_namespace_id  = data.terraform_remote_state.hub.outputs.cloudmap_namespace_id
  service_discovery_name = "reference-service-direct"

  tags = var.tags
}
