resource "aws_ecr_repository" "this" {
  name                 = "${var.name_prefix}/${var.repo_name}"
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}/${var.repo_name}" })
}

locals {
  default_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_expire_days} day(s)"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expire_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep only the last ${var.max_image_count} tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.max_image_count
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy     = coalesce(var.lifecycle_policy_json, local.default_lifecycle_policy)
}
