module "ecr" {
  source   = "../modules/ecr-repo"
  for_each = var.ecr_repo_names

  name_prefix = var.name_prefix
  repo_name   = each.value
  tags        = var.tags
}
