variable "name_prefix" {
  description = "Prefix applied to the cluster name and related tags."
  type        = string
  default     = "failure-mode-circus"
}

variable "vpc_id" {
  description = "VPC the Cloud Map private DNS namespace is associated with (from the networking module)."
  type        = string
}

variable "namespace_name" {
  description = "Cloud Map / Service Connect private DNS namespace name. Services get DNS names like <service>.<namespace_name>, e.g. reference-service.internal."
  type        = string
  default     = "internal"
}

variable "enable_container_insights" {
  description = "Whether to enable CloudWatch Container Insights on the cluster. Defaults to false to avoid its extra CloudWatch cost on infra that's meant to be idle most of the time; opt in per-scenario if needed."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags merged onto every resource this module creates."
  type        = map(string)
  default     = {}
}
