variable "name_prefix" {
  description = "Prefix applied to Name tags and endpoint/security-group names created by this module."
  type        = string
  default     = "failure-mode-circus"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "One CIDR per private subnet; each subnet is placed in a different available AZ (in order). Defaults to 2, matching the hub's 2-AZ requirement."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "tags" {
  description = "Additional tags merged onto every resource this module creates."
  type        = map(string)
  default     = {}
}
