# AWS AgentCore Workshop: MarketPulse - Terraform Outputs
# Outputs for workshop progression and testing

# ============================================================================
# ECR Repository
# ============================================================================

output "ecr_repository_name" {
  description = "Name of the ECR repository for the agent container"
  value       = aws_ecr_repository.agent.name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.agent.repository_url
}

# ============================================================================
# AgentCore Runtime
# ============================================================================

output "runtime_name" {
  description = "Name of the AgentCore Runtime"
  value       = awscc_bedrockagentcore_runtime.agent.agent_runtime_name
}

output "agent_runtime_id" {
  description = "ID of the AgentCore Runtime"
  value       = awscc_bedrockagentcore_runtime.agent.id
}

output "agent_runtime_arn" {
  description = "ARN of the AgentCore Runtime (required for InvokeAgentRuntime API)"
  value       = "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}:runtime/${awscc_bedrockagentcore_runtime.agent.id}"
}

output "agent_endpoint_id" {
  description = "ID of the AgentCore Runtime Endpoint"
  value       = awscc_bedrockagentcore_runtime_endpoint.agent.id
}

output "agent_endpoint_name" {
  description = "Name of the AgentCore Runtime Endpoint (use as qualifier)"
  value       = awscc_bedrockagentcore_runtime_endpoint.agent.name
}

# ============================================================================
# AgentCore Gateway (Module 2+)
# ============================================================================

output "gateway_id" {
  description = "ID of the AgentCore Gateway"
  value       = local.gateway_id
  sensitive   = true
}

output "gateway_role_arn" {
  description = "ARN of the Gateway IAM role"
  value       = var.enable_gateway ? aws_iam_role.gateway[0].arn : null
}

output "finnhub_target_configured" {
  description = "Whether the Finnhub HTTP target is configured"
  value       = var.enable_http_target
}

output "openapi_spec_bucket" {
  description = "S3 bucket containing OpenAPI specifications"
  value       = var.enable_http_target ? aws_s3_bucket.openapi_specs[0].id : null
}

# ============================================================================
# Lambda Risk Scorer (Module 3)
# ============================================================================

output "lambda_function_name" {
  description = "Name of the risk scorer Lambda function"
  value       = var.enable_lambda_target ? aws_lambda_function.risk_scorer[0].function_name : null
}

output "lambda_function_arn" {
  description = "ARN of the risk scorer Lambda function"
  value       = var.enable_lambda_target ? aws_lambda_function.risk_scorer[0].arn : null
}

output "lambda_log_group" {
  description = "CloudWatch log group for Lambda execution logs"
  value       = var.enable_lambda_target ? aws_cloudwatch_log_group.risk_scorer[0].name : null
}

output "lambda_target_configured" {
  description = "Whether the Lambda Gateway target is configured"
  value       = var.enable_lambda_target
}

# ============================================================================
# MCP Server (Module 4)
# ============================================================================

output "ecr_mcp_repository_url" {
  description = "URL of the ECR repository for the MCP server container"
  value       = var.enable_mcp_target ? aws_ecr_repository.mcp_server[0].repository_url : null
}

output "mcp_server_runtime_name" {
  description = "Name of the AgentCore Runtime for the MCP server"
  value       = var.enable_mcp_target ? awscc_bedrockagentcore_runtime.mcp[0].agent_runtime_name : null
}

output "mcp_server_runtime_id" {
  description = "ID of the AgentCore Runtime for the MCP server"
  value       = var.enable_mcp_target ? awscc_bedrockagentcore_runtime.mcp[0].id : null
}

output "mcp_server_endpoint_name" {
  description = "Name of the AgentCore Runtime Endpoint for the MCP server (use as qualifier)"
  value       = var.enable_mcp_target ? awscc_bedrockagentcore_runtime_endpoint.mcp[0].name : null
}

output "mcp_target_configured" {
  description = "Whether the MCP Gateway target is configured"
  value       = var.enable_mcp_target
}

# ============================================================================
# Workshop Progress
# ============================================================================

output "enabled_modules" {
  description = "Summary of enabled workshop modules"
  value = {
    phase_1_foundation    = true # Configuration only, no resources
    phase_2_runtime_http  = var.enable_gateway && var.enable_http_target
    phase_3_lambda        = var.enable_lambda_target
    phase_4_mcp           = var.enable_mcp_target
    phase_5_memory        = var.enable_memory
    phase_6_identity      = var.enable_identity
    phase_7_observability = var.enable_observability
  }
}

# Determine next workshop phase based on current state
locals {
  next_phase_map = [
    { enabled = var.enable_observability, message = "All phases complete!" },
    { enabled = var.enable_identity, message = "Phase 7: Enable observability" },
    { enabled = var.enable_memory, message = "Phase 6: Enable identity" },
    { enabled = var.enable_mcp_target, message = "Phase 5: Enable memory" },
    { enabled = var.enable_lambda_target, message = "Phase 4: Enable MCP target" },
    { enabled = var.enable_http_target, message = "Phase 3: Enable Lambda target" },
    { enabled = var.enable_gateway, message = "Phase 2: Enable HTTP target" },
  ]

  # Find first incomplete phase (iterates through list until it finds false)
  next_phase_determined = [
    for phase in local.next_phase_map : phase.message
    if !phase.enabled
  ]

  next_phase_final = length(local.next_phase_determined) > 0 ? local.next_phase_determined[0] : "Phase 2: Enable gateway and runtime"
}

# ============================================================================
# Test Instructions
# ============================================================================

output "test_command" {
  description = "Command to test the deployed agent"
  value       = "python scripts/test-agent.py"
}

output "next_phase" {
  description = "Suggested next phase to enable"
  value       = local.next_phase_final
}
