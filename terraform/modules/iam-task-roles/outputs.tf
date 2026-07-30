output "execution_role_arn" {
  description = "ARN of the shared ECS task execution role, or null if create_execution_role = false."
  value       = var.create_execution_role ? aws_iam_role.execution[0].arn : null
}

output "execution_role_name" {
  description = "Name of the shared ECS task execution role, or null if create_execution_role = false."
  value       = var.create_execution_role ? aws_iam_role.execution[0].name : null
}

output "task_role_arns" {
  description = "Map of logical scenario name -> task role ARN, one entry per var.task_roles."
  value       = { for k, v in aws_iam_role.task : k => v.arn }
}

output "task_role_names" {
  description = "Map of logical scenario name -> task role name, one entry per var.task_roles."
  value       = { for k, v in aws_iam_role.task : k => v.name }
}
