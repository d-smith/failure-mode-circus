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

  # Maps a port_mappings `name` to its container port, so
  # service_connect_services entries don't have to repeat the port number.
  port_by_name = merge([
    for c in var.containers : {
      for p in c.port_mappings : p.name => p.container_port if p.name != null
    }
  ]...)
}

# Classic Cloud Map service discovery, independent of Service Connect above -
# a plain Route 53 private-hosted-zone A record any VPC resource can resolve,
# for clients (like a standalone k6-runner RunTask) that can't enroll in
# Service Connect's proxy-based DNS at all.
resource "aws_service_discovery_service" "direct" {
  count = var.cloudmap_namespace_id != null ? 1 : 0

  name = coalesce(var.service_discovery_name, "${var.service_name}-direct")

  dns_config {
    namespace_id = var.cloudmap_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-${var.service_name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  container_definitions    = jsonencode(local.container_definitions)

  tags = merge(var.tags, { Name = "${var.name_prefix}-${var.service_name}" })
}

resource "aws_ecs_service" "this" {
  name            = var.service_name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = concat([aws_security_group.service.id], var.extra_security_group_ids)
    assign_public_ip = false
  }

  dynamic "service_registries" {
    for_each = var.cloudmap_namespace_id != null ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.direct[0].arn
    }
  }

  service_connect_configuration {
    enabled = var.enable_service_connect

    dynamic "service" {
      for_each = var.enable_service_connect ? var.service_connect_services : []
      content {
        port_name      = service.value.port_name
        discovery_name = service.value.discovery_name

        client_alias {
          port     = coalesce(service.value.client_port, local.port_by_name[service.value.port_name])
          dns_name = service.value.discovery_name
        }
      }
    }
  }

  tags = merge(var.tags, { Name = var.service_name })
}
