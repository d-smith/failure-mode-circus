data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, length(var.private_subnet_cidrs))
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(var.tags, { Name = "${var.name_prefix}-private-${local.azs[count.index]}" })
}

# Single shared route table for all private subnets: with no NAT Gateway,
# there is no per-AZ egress route to differentiate on, only the S3 gateway
# endpoint route added below plus the implicit local VPC route.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-private-rt" })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
