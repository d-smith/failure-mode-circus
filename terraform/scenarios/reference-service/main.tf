terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Hub's outputs.tf is a stable contract (only ever appended to) - see
# terraform/hub/outputs.tf.
data "terraform_remote_state" "hub" {
  backend = "s3"

  config = {
    bucket = var.hub_state_bucket
    key    = var.hub_state_key
    region = var.aws_region
  }
}
