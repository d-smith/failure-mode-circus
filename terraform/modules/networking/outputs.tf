output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the created VPC."
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, one per AZ."
  value       = aws_subnet.private[*].id
}

output "availability_zones" {
  description = "AZs the private subnets were placed in, same order as private_subnet_ids."
  value       = local.azs
}

output "private_route_table_id" {
  description = "Route table shared by all private subnets."
  value       = aws_route_table.private.id
}

output "vpc_endpoints_security_group_id" {
  description = "Security group attached to the interface VPC endpoints' ENIs. Ingress already permits HTTPS from the whole VPC CIDR, so tasks needing to reach ECR/CloudWatch Logs don't need to be added to it explicitly."
  value       = aws_security_group.vpc_endpoints.id
}
