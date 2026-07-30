data "aws_region" "current" {}

# Fargate tasks in fully private subnets reach ECR (image pulls) and
# CloudWatch Logs (log delivery) via these interface endpoints instead of a
# NAT Gateway. S3 uses the free gateway endpoint below for the same reason.
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.name_prefix}-vpce-"
  description = "Allows HTTPS from within the VPC to interface VPC endpoints (ECR, CloudWatch Logs)."
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from within the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpce-sg" })
}

locals {
  interface_endpoint_services = ["ecr.api", "ecr.dkr", "logs"]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoint_services)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpce-${each.value}" })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpce-s3" })
}
