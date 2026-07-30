variable "name_prefix" {
  description = "Prefix applied to role names and tags."
  type        = string
  default     = "failure-mode-circus"
}

variable "create_execution_role" {
  description = "Whether to create the shared ECS task execution role in this call. Set true once, where it's instantiated for all scenarios to share (the hub); scenario root modules should reference that output rather than creating their own."
  type        = bool
  default     = true
}

variable "task_roles" {
  description = "Per-scenario ECS task roles to create, keyed by a logical scenario name (e.g. \"reference-service\"). Each gets the standard ecs-tasks.amazonaws.com trust policy plus whatever managed policy ARNs are listed; an empty managed_policy_arns list creates a role with no extra permissions, for scenarios that need none."
  type = map(object({
    managed_policy_arns = optional(list(string), [])
  }))
  default = {}
}

variable "tags" {
  description = "Additional tags merged onto every role this module creates."
  type        = map(string)
  default     = {}
}
