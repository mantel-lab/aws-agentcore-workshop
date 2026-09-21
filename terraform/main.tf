# AWS AgentCore Workshop: MarketPulse - Main Configuration
# Terraform configuration for progressive AgentCore feature deployment

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 0.24.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0.0"
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

# Catch feature flag combinations that cannot work, before anything is created
resource "terraform_data" "feature_flags" {
  input = {
    gateway  = var.enable_gateway
    http     = var.enable_http_target
    lambda   = var.enable_lambda_target
    mcp      = var.enable_mcp_target
    identity = var.enable_identity
  }

  lifecycle {
    precondition {
      condition     = !(var.enable_http_target || var.enable_lambda_target || var.enable_mcp_target) || var.enable_gateway
      error_message = "Gateway targets require enable_gateway = true."
    }

    precondition {
      condition     = !var.enable_identity || var.enable_mcp_target
      error_message = "enable_identity secures the MCP target, so it requires enable_mcp_target = true."
    }

    precondition {
      condition     = !var.enable_http_target || length(var.finnhub_api_key) > 0
      error_message = "enable_http_target requires finnhub_api_key to be set in terraform.tfvars."
    }
  }
}