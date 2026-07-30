output "log_group_names" {
  description = "Map of logical name -> full CloudWatch log group name, one entry per var.log_group_names."
  value       = { for k, v in aws_cloudwatch_log_group.this : k => v.name }
}

output "log_group_arns" {
  description = "Map of logical name -> log group ARN, one entry per var.log_group_names."
  value       = { for k, v in aws_cloudwatch_log_group.this : k => v.arn }
}
