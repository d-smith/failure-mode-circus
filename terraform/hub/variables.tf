variable "name_prefix" {
  description = "Prefix applied to resource names/tags across every module the hub composes."
  type        = string
  default     = "failure-mode-circus"
}

variable "log_group_names" {
  description = "Logical names for the CloudWatch log groups the hub creates via the logging module. Extend this list when a new scenario needs its own log group."
  type        = set(string)
  default     = ["reference-service", "k6-runner"]
}

variable "tags" {
  description = "Tags applied to every resource created by modules the hub composes."
  type        = map(string)
  default = {
    Project   = "failure-mode-circus"
    ManagedBy = "terraform"
  }
}

variable "ecr_repo_names" {
  description = "Names of ECR repositories to create, one per container image the pipeline builds/pushes. for_each-driven off this list (see terraform.tfvars) so adding a new scenario's image is a one-line addition."
  type        = set(string)
}

variable "github_repo" {
  description = "GitHub repo the OIDC-trusted roles trust, in the sub-claim form GitHub actually sends. Uses the owner@ownerId/repo@repoId immutable-ID format GitHub switches to once an account/repo has been renamed - confirmed against a live AssumeRoleWithWebIdentity denial in CloudTrail (task 29) - rather than the plain owner/repo form."
  type        = string
  default     = "d-smith@758310/failure-mode-circus@1315382562"
}
