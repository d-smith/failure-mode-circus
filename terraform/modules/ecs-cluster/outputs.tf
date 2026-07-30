output "cluster_arn" {
  description = "ARN of the ECS cluster."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "cloudmap_namespace_id" {
  description = "ID of the Cloud Map private DNS namespace backing Service Connect."
  value       = aws_service_discovery_private_dns_namespace.this.id
}

output "cloudmap_namespace_arn" {
  description = "ARN of the Cloud Map private DNS namespace, set as the cluster's Service Connect default namespace."
  value       = aws_service_discovery_private_dns_namespace.this.arn
}
