# Stable contract for scenario root modules reading this via
# terraform_remote_state: only add outputs here, never rename or remove one.

output "vpc_id" {
  description = "ID of the shared VPC."
  value       = module.networking.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the shared VPC, for scoping scenario security group ingress."
  value       = module.networking.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs scenario tasks/services run in."
  value       = module.networking.private_subnet_ids
}

output "cluster_arn" {
  description = "ARN of the shared ECS cluster."
  value       = module.ecs_cluster.cluster_arn
}

output "cloudmap_namespace_id" {
  description = "ID of the Cloud Map private DNS namespace backing Service Connect."
  value       = module.ecs_cluster.cloudmap_namespace_id
}

output "ecr_repository_urls" {
  description = "Map of logical image name -> ECR repository URL, one entry per var.ecr_repo_names."
  value       = { for k, v in module.ecr : k => v.repository_url }
}

output "oidc_terraform_apply_role_arn" {
  description = "ARN of the OIDC-trusted terraform-apply role, for terraform-hub.yml / terraform-scenario.yml's role-to-assume."
  value       = module.oidc_terraform_apply.role_arn
}

output "oidc_build_and_push_role_arn" {
  description = "ARN of the OIDC-trusted build-and-push/deploy role, for build-and-push.yml / deploy-service.yml / run-k6-task.yml's role-to-assume."
  value       = module.oidc_build_and_push.role_arn
}
