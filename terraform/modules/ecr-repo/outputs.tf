output "repository_url" {
  description = "Repository URL, for use in docker build/push and task definition image references."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN of the repository."
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Full repository name (<name_prefix>/<repo_name>)."
  value       = aws_ecr_repository.this.name
}
