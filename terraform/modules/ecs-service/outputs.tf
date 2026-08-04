output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "ARN of the registered task definition (includes revision)."
  value       = aws_ecs_task_definition.this.arn
}

output "security_group_id" {
  description = "ID of the security group created for this service's tasks."
  value       = aws_security_group.service.id
}

output "service_discovery_name" {
  description = "Classic Cloud Map DNS label registered for this service (null if cloudmap_namespace_id wasn't set) - combine with the namespace's own name for the full DNS name, e.g. \"<this>.internal\"."
  value       = var.cloudmap_namespace_id != null ? coalesce(var.service_discovery_name, "${var.service_name}-direct") : null
}
