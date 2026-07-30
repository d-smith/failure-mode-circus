resource "aws_service_discovery_private_dns_namespace" "this" {
  name = var.namespace_name
  vpc  = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-${var.namespace_name}" })
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  service_connect_defaults {
    namespace = aws_service_discovery_private_dns_namespace.this.arn
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-cluster" })
}
