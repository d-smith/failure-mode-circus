output "task_definition_arn" {
  description = "ARN of the registered task definition (includes revision)."
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "Task family name, for use with `aws ecs run-task --task-definition`."
  value       = aws_ecs_task_definition.this.family
}

output "security_group_id" {
  description = "ID of the security group created for this task, for use in the run-task invocation's network configuration."
  value       = aws_security_group.task.id
}
