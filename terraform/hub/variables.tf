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
