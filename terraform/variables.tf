# AWS AgentCore Workshop: MarketPulse - Terraform Variables
# Feature flags enable progressive workshop module deployment

# ============================================================================
# Feature Flags - Enable progressively during workshop
# ============================================================================

variable "enable_gateway" {
  description = "Enable AgentCore Gateway (Module 2+)"
  type        = bool
  default     = false
}

variable "enable_http_target" {
  description = "Enable HTTP Gateway target for Finnhub stock API (Module 2)"
  type        = bool
  default     = false
}

variable "enable_lambda_target" {
  description = "Enable Lambda Gateway target for risk scoring (Module 3)"
  type        = bool
  default     = false
}

variable "enable_mcp_target" {
  description = "Enable MCP Server Gateway target for market calendar (Module 4)"
  type        = bool
  default     = false
}

variable "enable_memory" {
  description = "Enable AgentCore Memory for persistent context (Module 5)"
  type        = bool
  default     = false
}

variable "enable_identity" {
  description = "Enable AgentCore Identity with OAuth 2.0 (Module 6)"
  type        = bool
  default     = false
}

variable "enable_observability" {
  description = "Enable AgentCore Observability with tracing (Module 7)"
  type        = bool
  default     = false
}

# ============================================================================
# Core Configuration
# ============================================================================

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "marketpulse-workshop"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# ============================================================================
# Bedrock Configuration
# ============================================================================

variable "bedrock_model_id" {
  description = "Bedrock model ID for the agent"
  type        = string
  default     = "anthropic.claude-sonnet-4-5-20250929-v1:0"
}

variable "model_max_tokens" {
  description = "Maximum tokens for model responses"
  type        = number
  default     = 4096
}

variable "model_temperature" {
  description = "Temperature for model inference"
  type        = number
  default     = 0.7
}

# ============================================================================
# API Configuration
# ============================================================================

variable "finnhub_api_key" {
  description = "Finnhub API key for stock price data (stored in Secrets Manager). Required when enable_http_target = true"
  type        = string
  sensitive   = true
  default     = ""
}

# ============================================================================
# Network Configuration
# ============================================================================

variable "network_mode" {
  description = "Network mode for AgentCore Runtime (PUBLIC for workshop simplicity)"
  type        = string
  default     = "PUBLIC"
}

# ============================================================================
# Memory Configuration
# ============================================================================

variable "memory_event_expiry_days" {
  description = "Number of days before memory events expire"
  type        = number
  default     = 90
}

variable "memory_strategy" {
  description = "Memory extraction strategy"
  type        = string
  default     = "user_preference_memory_strategy"
  validation {
    condition     = contains(["user_preference_memory_strategy", "semantic_memory_strategy", "summary_memory_strategy"], var.memory_strategy)
    error_message = "Memory strategy must be one of: user_preference_memory_strategy, semantic_memory_strategy, summary_memory_strategy"
  }
}

# ============================================================================
# Observability Configuration
# ============================================================================

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for observability"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 7
}

# ============================================================================
# Tags
# ============================================================================

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "MarketPulse Workshop"
    ManagedBy   = "Terraform"
    Environment = "dev"
    Workshop    = "AgentCore"
  }
}