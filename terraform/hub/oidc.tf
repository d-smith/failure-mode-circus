data "aws_caller_identity" "current" {}

# Created out-of-band by terraform/bootstrap/oidc.tf; looked up here rather
# than coupled to bootstrap's local state.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  account_id       = data.aws_caller_identity.current.account_id
  iam_role_pattern = "arn:aws:iam::${local.account_id}:role/${var.name_prefix}-*"
}

# Broad-but-scoped: this role has to be able to create/manage the IAM roles,
# VPC/networking, ECS, ECR, log groups, and Cloud Map resources every module
# in this repo defines, so within those services it's close to unrestricted.
# It is NOT AdministratorAccess - IAM write and PassRole are scoped to this
# project's own role-name prefix, and it can't touch unrelated AWS services.
data "aws_iam_policy_document" "terraform_apply" {
  statement {
    sid       = "Ec2Networking"
    actions   = ["ec2:*"]
    resources = ["*"]
  }

  statement {
    sid       = "EcsFull"
    actions   = ["ecs:*"]
    resources = ["*"]
  }

  statement {
    sid       = "ServiceDiscoveryFull"
    actions   = ["servicediscovery:*"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrAccountLevel"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrRepos"
    actions   = ["ecr:*"]
    resources = ["arn:aws:ecr:*:${local.account_id}:repository/${var.name_prefix}/*"]
  }

  statement {
    sid       = "LogGroups"
    actions   = ["logs:*"]
    resources = ["arn:aws:logs:*:${local.account_id}:log-group:/ecs/${var.name_prefix}*:*"]
  }

  # logs:DescribeLogGroups doesn't support resource-level scoping the way
  # other logs:* actions do - AWS evaluates it against a fixed "list all"
  # resource pattern (empty log-group segment) rather than a named log
  # group ARN, so it has to be granted account-wide like ec2:*/ecs:*/
  # servicediscovery:* above. Confirmed via a live `terraform plan`
  # AccessDeniedException (task 29).
  statement {
    sid       = "LogsDescribeAccountWide"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    sid       = "IamReadOnly"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  statement {
    sid = "IamManageProjectRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PassRole",
    ]
    resources = [local.iam_role_pattern]
  }

  statement {
    sid       = "IamReadGithubOidcProvider"
    actions   = ["iam:GetOpenIDConnectProvider"]
    resources = [data.aws_iam_openid_connect_provider.github.arn]
  }

  statement {
    sid     = "TerraformStateBucket"
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [
      "arn:aws:s3:::failure-mode-circus-tfstate-${local.account_id}",
      "arn:aws:s3:::failure-mode-circus-tfstate-${local.account_id}/*",
    ]
  }

  statement {
    sid       = "TerraformLockTable"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = ["arn:aws:dynamodb:*:${local.account_id}:table/failure-mode-circus-tflock"]
  }
}

# Narrow: only what the day-to-day build/push/deploy/run-k6 workflow steps
# need. No IAM role or policy write, no EC2/VPC actions at all.
data "aws_iam_policy_document" "build_and_push_deploy" {
  statement {
    sid       = "EcrAccountLevel"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = ["arn:aws:ecr:*:${local.account_id}:repository/${var.name_prefix}/*"]
  }

  statement {
    sid = "EcsDeployAndRunTask"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:UpdateService",
      "ecs:DescribeServices",
      "ecs:DescribeTasks",
      "ecs:RunTask",
      "ecs:StopTask",
      "ecs:ListTasks",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PassProjectTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [local.iam_role_pattern]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

module "oidc_terraform_apply" {
  source = "../modules/github-oidc-role"

  name_prefix         = var.name_prefix
  purpose             = "terraform-apply"
  oidc_provider_arn   = data.aws_iam_openid_connect_provider.github.arn
  github_repo         = var.github_repo
  github_branch       = "main"
  allow_pull_requests = true # terraform-hub.yml plans on PR, applies on merge to main
  inline_policy_json  = data.aws_iam_policy_document.terraform_apply.json

  tags = var.tags
}

module "oidc_build_and_push" {
  source = "../modules/github-oidc-role"

  name_prefix         = var.name_prefix
  purpose             = "build-and-push"
  oidc_provider_arn   = data.aws_iam_openid_connect_provider.github.arn
  github_repo         = var.github_repo
  github_branch       = "main"
  allow_pull_requests = false
  inline_policy_json  = data.aws_iam_policy_document.build_and_push_deploy.json

  tags = var.tags
}
