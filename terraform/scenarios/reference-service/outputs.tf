output "service_name" {
  description = "Name of the reference-service ECS service."
  value       = module.reference_service.service_name
}

output "task_definition_arn" {
  description = "ARN of the registered reference-service task definition."
  value       = module.reference_service.task_definition_arn
}

output "security_group_id" {
  description = "ID of the reference-service task's security group."
  value       = module.reference_service.security_group_id
}
