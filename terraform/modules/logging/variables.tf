variable "name_prefix" {
  description = "Prefix applied to the log group naming convention and tags."
  type        = string
  default     = "failure-mode-circus"
}

variable "log_group_names" {
  description = "Logical names for the log groups to create; each becomes /ecs/<name_prefix>/<name>, e.g. \"reference-service\" -> /ecs/failure-mode-circus/reference-service."
  type        = set(string)
}

variable "retention_in_days" {
  description = "CloudWatch Logs retention period in days, applied to every log group this module creates. Defaults to 7 (short, since this infra is meant to be idle/low-cost most of the time). Pass 0 for never-expire."
  type        = number
  default     = 7

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.retention_in_days)
    error_message = "retention_in_days must be a value CloudWatch Logs accepts (0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, ...)."
  }
}

variable "tags" {
  description = "Additional tags merged onto every log group this module creates."
  type        = map(string)
  default     = {}
}
