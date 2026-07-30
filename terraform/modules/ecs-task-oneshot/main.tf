data "aws_region" "current" {}

locals {
  container_definitions = [
    for c in var.containers : {
      name              = c.name
      image             = c.image
      essential         = c.essential
      cpu               = c.cpu
      memory            = c.memory
      memoryReservation = c.memory_reservation
      command           = c.command
      environment       = [for e in c.environment : { name = e.name, value = e.value }]
      secrets           = [for s in c.secrets : { name = s.name, valueFrom = s.value_from }]
      portMappings = [
        for p in c.port_mappings : {
          name          = p.name
          containerPort = p.container_port
          appProtocol   = p.app_protocol
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = c.name
        }
      }
    }
  ]
}

# Task definition only - this is run via `aws ecs run-task`, not as an
# aws_ecs_service, so network placement (subnets) and any Service Connect
# client configuration are supplied at run-task invocation time by the
# calling workflow, not baked into Terraform state here.
resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-${var.task_name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  container_definitions    = jsonencode(local.container_definitions)

  tags = merge(var.tags, { Name = "${var.name_prefix}-${var.task_name}" })
}
