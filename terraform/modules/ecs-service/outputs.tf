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
