# AWS AgentCore Workshop: MarketPulse - Lambda Configuration
# Module 3: Lambda Gateway Target
# To be implemented in Phase 3

# ============================================================================
# IAM Role for Lambda Function
# ============================================================================
# TODO: Implement in Phase 3 when enable_lambda_target = true
# - Create execution role for Lambda function
# - Attach CloudWatch Logs policy
# - Configure trust relationship with Lambda service

# ============================================================================
# Lambda Function - Risk Profile Scorer
# ============================================================================
# TODO: Implement in Phase 3 when enable_lambda_target = true
# - Create Lambda function for risk scoring
# - Configure runtime environment (Python 3.11+)
# - Set up function code from lambda/ directory
# - Configure environment variables
# - Set appropriate timeout and memory

# ============================================================================
# Lambda Gateway Target
# ============================================================================
# TODO: Implement in Phase 3 when enable_lambda_target = true
# - Create Lambda Gateway Target
# - Link Lambda function to gateway
# - Configure invocation permissions

# ============================================================================
# Placeholder Resources for Phase 1 Validation (count = 0)
# ============================================================================
# These exist only to satisfy outputs.tf references during terraform validate

resource "aws_lambda_function" "risk_scorer" {
  count         = 0
  function_name = local.lambda_function_name
  role          = ""
  handler       = "risk_scorer.handler"
  runtime       = "python3.11"
  filename      = "dummy.zip"
}

# Placeholder for Lambda gateway target (Phase 3)
# resource "aws_bedrock_agent_gateway_target" "lambda" {
#   count = 0
#   name  = "${local.gateway_name}-lambda"
# }
