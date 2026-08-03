variable "name_prefix" {
  description = "Prefix applied to the role name and tags."
  type        = string
  default     = "failure-mode-circus"
}

variable "purpose" {
  description = "Short identifier for what this role is used for, e.g. \"terraform-apply\" or \"build-and-push\"; becomes part of the role name."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider (terraform/bootstrap/oidc.tf's github_oidc_provider_arn output)."
  type        = string
}

variable "github_repo" {
  description = "The exact value GitHub sends in the OIDC sub claim's repo segment - normally \"owner/repo\", but if the account or repo has ever been renamed, GitHub switches to the immutable-ID form \"owner@ownerId/repo@repoId\" instead. Verify against a live token (e.g. a CloudTrail AssumeRoleWithWebIdentity denial) rather than assuming the plain form."
  type        = string
}

variable "github_branch" {
  description = "Branch (without the refs/heads/ prefix) this role's trust policy is scoped to. Matched with StringLike, so a caller needing a wider match can pass a pattern like \"*\" or \"feature/*\"."
  type        = string
  default     = "main"
}

variable "allow_pull_requests" {
  description = "If true, also trust workflow runs triggered by a pull_request event against this repo (any branch) — for plan-only roles assumed by PR-triggered workflows."
  type        = bool
  default     = false
}

variable "policy_arns" {
  description = "Managed policy ARNs to attach to the role."
  type        = list(string)
  default     = []
}

variable "inline_policy_json" {
  description = "An aws_iam_policy_document JSON string to attach as an inline policy, or null to skip. Lets each purpose get exactly the permissions it needs (e.g. a narrow ECR-push-plus-ECS-deploy policy) without this module hardcoding them."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags merged onto the role."
  type        = map(string)
  default     = {}
}
