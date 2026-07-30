variable "name_prefix" {
  description = "Prefix applied to the task family name and tags."
  type        = string
  default     = "failure-mode-circus"
}

variable "task_name" {
  description = "Logical task name, e.g. \"k6-runner\". Used as the task family suffix."
  type        = string
}

variable "vpc_id" {
  description = "VPC to place the task's security group in."
  type        = string
}

variable "execution_role_arn" {
  description = "ECS task execution role ARN (from the iam-task-roles module's shared execution role)."
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN (from the iam-task-roles module's per-scenario task role)."
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group name every container in this task logs to (from the logging module)."
  type        = string
}

variable "containers" {
  description = "List of container definitions for the task. Same shape as the ecs-service module's containers variable."
  type = list(object({
    name               = string
    image              = string
    essential          = optional(bool, true)
    cpu                = optional(number)
    memory             = optional(number)
    memory_reservation = optional(number)
    command             = optional(list(string))
    environment = optional(list(object({
      name  = string
      value = string
    })), [])
    secrets = optional(list(object({
      name       = string
      value_from = string
    })), [])
    port_mappings = optional(list(object({
      container_port = number
      name           = optional(string)
      app_protocol   = optional(string, "http")
    })), [])
  }))
}

variable "task_cpu" {
  description = "Fargate task-level CPU units."
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Fargate task-level memory (MiB)."
  type        = string
  default     = "512"
}

variable "tags" {
  description = "Additional tags merged onto every resource this module creates."
  type        = map(string)
  default     = {}
}
