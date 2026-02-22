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

# ============================================================================
# Test Instructions
# ============================================================================

output "test_command" {
  description = "Command to test the deployed agent"
  value       = "python scripts/test-agent.py"
}

output "next_phase" {
  description = "Suggested next phase to enable"
  value = var.enable_observability ? "All phases complete!" : (
    var.enable_identity ? "Phase 7: Enable observability" : (
      var.enable_memory ? "Phase 6: Enable identity" : (
        var.enable_mcp_target ? "Phase 5: Enable memory" : (
          var.enable_lambda_target ? "Phase 4: Enable MCP target" : (
            var.enable_http_target ? "Phase 3: Enable Lambda target" : (
              var.enable_gateway ? "Phase 2: Enable HTTP target" : "Phase 2: Enable gateway and runtime"
            )
          )
        )
      )
    )
  )
}
