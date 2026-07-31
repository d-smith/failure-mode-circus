variable "name_prefix" {
  description = "Prefix applied to resource names/tags, matching the hub's."
  type        = string
  default     = "failure-mode-circus"
}

variable "tags" {
  description = "Tags applied to every resource this scenario creates."
  type        = map(string)
  default = {
    Project   = "failure-mode-circus"
    ManagedBy = "terraform"
    Scenario  = "reference-service"
  }
}

variable "hub_state_bucket" {
  description = "S3 bucket holding the hub root module's remote state."
  type        = string
  default     = "failure-mode-circus-tfstate-427848627088"
}

variable "hub_state_key" {
  description = "State file key for the hub root module."
  type        = string
  default     = "hub/terraform.tfstate"
}

variable "aws_region" {
  description = "AWS region, matching the hub's."
  type        = string
  default     = "us-east-1"
}

variable "image_tag" {
  description = "Tag of the reference-service image to deploy from ECR."
  type        = string
  default     = "latest"
}

variable "k6_image_tag" {
  description = "Tag of the k6-runner image to use for the smoke-test task from ECR."
  type        = string
  default     = "latest"
}

variable "container_port" {
  description = "Port the reference-service container listens on."
  type        = number
  default     = 8080
}

variable "desired_count" {
  description = "Number of reference-service tasks the ECS service keeps running."
  type        = number
  default     = 1
}
