output "role_arn" {
  description = "ARN of the created role, for use in a workflow's `role-to-assume` input."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the created role."
  value       = aws_iam_role.this.name
}
