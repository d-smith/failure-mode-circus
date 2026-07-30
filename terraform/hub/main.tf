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
  region = "us-east-1"
}

module "networking" {
  source = "../modules/networking"

  name_prefix = var.name_prefix
  tags        = var.tags
}

module "ecs_cluster" {
  source = "../modules/ecs-cluster"

  name_prefix = var.name_prefix
  vpc_id      = module.networking.vpc_id
  tags        = var.tags
}

module "logging" {
  source = "../modules/logging"

  name_prefix     = var.name_prefix
  log_group_names = var.log_group_names
  tags            = var.tags
}
