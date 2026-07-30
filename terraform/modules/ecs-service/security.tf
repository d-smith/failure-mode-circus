locals {
  container_ports = distinct(flatten([
    for c in var.containers : [for p in c.port_mappings : p.container_port]
  ]))
}

resource "aws_security_group" "service" {
  name_prefix = "${var.name_prefix}-${var.service_name}-"
  description = "ECS service SG for ${var.service_name}: allows ingress on its container ports from within the VPC."
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = local.container_ports
    content {
      description = "Container port ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    }
  }

  egress {
    description = "All outbound - needed to reach VPC endpoints (ECR, CloudWatch Logs) and any other in-VPC dependency"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${var.service_name}-sg" })
}
