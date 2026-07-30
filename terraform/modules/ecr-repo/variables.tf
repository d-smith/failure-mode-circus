variable "name_prefix" {
  description = "Prefix applied to the repository name and tags."
  type        = string
  default     = "failure-mode-circus"
}

variable "repo_name" {
  description = "Repository name, e.g. \"reference-service\" or \"k6-runner\". Full repository name becomes \"<name_prefix>/<repo_name>\"."
  type        = string
}

variable "image_tag_mutability" {
  description = "Whether image tags can be overwritten once pushed."
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Whether to run ECR's basic image scan on every push."
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Lifecycle policy: keep only the most recent N tagged images (any tag pattern), expiring older ones. Ignored if lifecycle_policy_json is set."
  type        = number
  default     = 10
}

variable "untagged_expire_days" {
  description = "Lifecycle policy: expire untagged images after this many days. Ignored if lifecycle_policy_json is set."
  type        = number
  default     = 3
}

variable "lifecycle_policy_json" {
  description = "A full ECR lifecycle policy JSON string, overriding the default two-rule policy built from max_image_count/untagged_expire_days. Set to null to use the default."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags merged onto the repository."
  type        = map(string)
  default     = {}
}
