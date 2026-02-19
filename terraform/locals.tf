# AWS AgentCore Workshop: MarketPulse - Local Values
# Computed values and resource naming conventions

locals {
  # ============================================================================
  # Naming
  # ============================================================================

  name_prefix = "${var.project_name}-${var.environment}"

  # Resource names
  # Note: agent_runtime_name must match pattern [a-zA-Z][a-zA-Z0-9_]{0,47} (no hyphens)
  agent_name              = replace("${local.name_prefix}_agent", "-", "_")
  lambda_function_name    = "${local.name_prefix}-risk-scorer"
  mcp_server_name         = "${local.name_prefix}-mcp-server"
  memory_namespace        = "${local.name_prefix}-memory"
  ecr_repository_name     = "${local.name_prefix}-agent"
  ecr_mcp_repository_name = "${local.name_prefix}-mcp-server"

  # Runtime endpoint name (must use underscores, not hyphens)
  # AWS validation: ^[a-zA-Z][a-zA-Z0-9_]{0,47}$
  runtime_endpoint_name = replace("${local.name_prefix}_agent_endpoint", "-", "_")

  # ============================================================================
  # ARNs and Account Information
  # ============================================================================

  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.id

  # ============================================================================
  # Tags
  # ============================================================================

  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
      Project     = var.project_name
    }
  )

  # ============================================================================
  # Container Image URIs
  # ============================================================================

  agent_image_uri      = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com/${local.ecr_repository_name}:latest"
  mcp_server_image_uri = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com/${local.ecr_mcp_repository_name}:latest"

  # ============================================================================
  # API Endpoints
  # ============================================================================

  finnhub_base_url = "https://finnhub.io/api/v1"

  # ============================================================================
  # CloudWatch
  # ============================================================================

  log_group_name = "/aws/bedrock/agent/${local.agent_name}"
}