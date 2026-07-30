resource "aws_security_group" "task" {
  name_prefix = "${var.name_prefix}-${var.task_name}-"
  description = "ECS oneshot task SG for ${var.task_name}: outbound only, no inbound listeners expected."
  vpc_id      = var.vpc_id

  egress {
    description = "All outbound - reach VPC endpoints (ECR, CloudWatch Logs) and any in-VPC service under test"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${var.task_name}-sg" })
}
