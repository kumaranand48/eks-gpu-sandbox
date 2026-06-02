terraform {
  required_version = ">= 1.5"

  # Backend config is injected by Terragrunt's remote_state (see common.hcl).
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
  # Single account — no assume_role.
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
