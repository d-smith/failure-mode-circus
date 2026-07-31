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

output "k6_task_definition_arn" {
  description = "ARN of the registered k6-runner task definition, for run-k6-task.yml's `aws ecs run-task --task-definition`."
  value       = module.k6_runner.task_definition_arn
}

output "k6_task_definition_family" {
  description = "Family name of the k6-runner task definition."
  value       = module.k6_runner.task_definition_family
}

output "k6_security_group_id" {
  description = "ID of the k6-runner task's security group, for run-k6-task.yml's network configuration."
  value       = module.k6_runner.security_group_id
}
