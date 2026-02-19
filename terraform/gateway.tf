# AWS AgentCore Workshop: MarketPulse - Gateway Configuration
# Module 2: AgentCore Gateway + HTTP Target
# To be implemented in Phase 2

# ============================================================================
# AgentCore Gateway
# ============================================================================
# Gateway that routes requests to different targets (HTTP, Lambda, MCP)
# NOTE: These resource types are not yet available in the AWS provider
# They will be implemented when the provider supports them

# resource "aws_bedrock_agent_gateway" "main" {
#   count = var.enable_gateway ? 1 : 0
#
#   name                 = "${local.agent_name}-gateway"
#   agent_runtime_id     = awscc_bedrockagentcore_runtime.agent.id
#   agent_runtime_region = var.aws_region
#
#   tags = local.common_tags
# }

# ============================================================================
# HTTP Target (Phase 2)
# ============================================================================
# Routes to HTTP endpoints (e.g., Finnhub API)
# NOTE: These resource types are not yet available in the AWS provider

# resource "aws_bedrock_agent_gateway_target" "http" {
#   count = var.enable_http_target ? 1 : 0
#
#   gateway_id = aws_bedrock_agent_gateway.main[0].id
#   name       = "http-target"
#
#   http_endpoint = {
#     url = "https://finnhub.io/api/v1"
#     headers = {
#       "X-Finnhub-Token" = var.finnhub_api_key
#     }
#   }
#
#   tags = local.common_tags
# }
