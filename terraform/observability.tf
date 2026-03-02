# AWS AgentCore Workshop: MarketPulse - Observability Configuration
# Module 7: CloudWatch Logs and X-Ray Tracing
#
# This module enables distributed tracing and observability for the MarketPulse agent.
# AgentCore Runtime automatically instruments agents when OpenTelemetry environment
# variables are configured. Traces are exported to AWS X-Ray and visible in CloudWatch.

# ============================================================================
# X-Ray IAM Policy for Agent Runtime
# ============================================================================

# Grant agent runtime permissions to send traces to X-Ray
resource "aws_iam_role_policy" "agent_xray_access" {
  count = var.enable_observability ? 1 : 0

  name = "${local.agent_name}-xray-access"
  role = aws_iam_role.agent_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
          "xray:GetSamplingStatisticSummaries"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# X-Ray Sampling Rule (Optional)
# ============================================================================

# Configure adaptive sampling for cost optimisation in production
# For workshop, we trace 100% of requests via environment variable
resource "aws_xray_sampling_rule" "marketpulse" {
  count = var.enable_observability ? 1 : 0

  rule_name      = "marketpulse-sampling" # Max 32 chars
  priority       = 1000
  version        = 1
  reservoir_size = 1
  fixed_rate     = 1.0
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = local.agent_name
  resource_arn   = "*"

  tags = local.common_tags
}

# ============================================================================
# CloudWatch Log Group for Structured Logs
# ============================================================================

# Log group specifically for trace-correlated logs
resource "aws_cloudwatch_log_group" "agent_traces" {
  count = var.enable_observability ? 1 : 0

  name              = "/aws/bedrock-agentcore/traces/${local.agent_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ============================================================================
# Outputs
# ============================================================================

output "observability_enabled" {
  description = "Whether observability is enabled"
  value       = var.enable_observability
}

output "xray_sampling_rule_name" {
  description = "X-Ray sampling rule name"
  value       = var.enable_observability ? aws_xray_sampling_rule.marketpulse[0].rule_name : null
}

output "trace_log_group" {
  description = "CloudWatch log group for trace-correlated logs"
  value       = var.enable_observability ? aws_cloudwatch_log_group.agent_traces[0].name : null
}