locals {
  allowed_subjects = concat(
    ["repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"],
    var.allow_pull_requests ? ["repo:${var.github_repo}:pull_request"] : []
  )
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.allowed_subjects
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name_prefix}-${var.purpose}"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(var.tags, { Name = "${var.name_prefix}-${var.purpose}" })
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  count = var.inline_policy_json != null ? 1 : 0

  name   = "${var.name_prefix}-${var.purpose}-inline"
  role   = aws_iam_role.this.id
  policy = var.inline_policy_json
}
