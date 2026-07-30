variable "name_prefix" {
  description = "Prefix applied to the task family name and tags."
  type        = string
  default     = "failure-mode-circus"
}

variable "service_name" {
  description = "Logical service name, e.g. \"reference-service\". Used as the ECS service name and task family suffix."
  type        = string
}

variable "vpc_id" {
  description = "VPC to place the service's security group in."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block, used to scope the service's security group ingress to in-VPC traffic only."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs the service's tasks run in."
  type        = list(string)
}

variable "cluster_arn" {
  description = "ARN of the ECS cluster to run this service on."
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
  description = "List of container definitions for the task. Each becomes one entry in the task definition's container_definitions; port_mappings entries with a `name` set are eligible to be exposed via service_connect_services."
  type = list(object({
    name               = string
    image              = string
    essential          = optional(bool, true)
    cpu                = optional(number)
    memory             = optional(number)
    memory_reservation = optional(number)
    command            = optional(list(string))
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

variable "desired_count" {
  description = "Number of tasks the service keeps running."
  type        = number
  default     = 1
}

variable "enable_service_connect" {
  description = "Whether to enable ECS Service Connect on this service. Left on by default even for services with nothing to expose, so they can still act as Service Connect clients of other services."
  type        = bool
  default     = true
}

variable "service_connect_services" {
  description = "Service Connect entries to expose from this task's containers. Each port_name must match a `name` set on one of var.containers[*].port_mappings; discovery_name becomes the DNS label under the cluster's namespace (e.g. discovery_name = \"reference-service\" -> reference-service.internal). This module doesn't infer naming itself — callers decide it."
  type = list(object({
    port_name      = string
    discovery_name = string
    client_port    = optional(number)
  }))
  default = []
}

variable "extra_security_group_ids" {
  description = "Additional security group IDs to attach to the service's tasks, beyond the one this module creates."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags merged onto every resource this module creates."
  type        = map(string)
  default     = {}
}
