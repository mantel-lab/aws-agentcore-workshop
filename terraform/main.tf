# AWS AgentCore Workshop: MarketPulse - Main Configuration
# Terraform configuration for progressive AgentCore feature deployment

terraform {
  required_version = ">= 1.0.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0.0"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 0.24.0"
    }
  }

  # Local backend for workshop simplicity
  # In production, use remote backend (S3 + DynamoDB)
  backend "local" {
    path = "terraform.tfstate"
  }
}

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

# AWS Cloud Control Provider (required for some AgentCore resources)
provider "awscc" {
  region = var.aws_region
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}