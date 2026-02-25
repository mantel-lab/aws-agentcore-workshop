# AWS AgentCore Workshop: MarketPulse - Lambda Configuration
# Module 3: Lambda Gateway Target
#
# Deploys a risk profile scoring Lambda and registers it as an AgentCore
# Gateway target. Engineers enable this module by setting:
#   enable_lambda_target = true

# ============================================================================
# Lambda Deployment Package
# ============================================================================

# Zip the scorer.py from the lambda/ directory
data "archive_file" "risk_scorer" {
  count = var.enable_lambda_target ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/../lambda/scorer.py"
  output_path = "${path.module}/../lambda/scorer.zip"
}

# ============================================================================
# IAM Role for Lambda Execution
# ============================================================================

resource "aws_iam_role" "risk_scorer" {
  count = var.enable_lambda_target ? 1 : 0

  name = "${local.name_prefix}-risk-scorer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Attach managed policy for basic Lambda execution (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "risk_scorer_basic" {
  count = var.enable_lambda_target ? 1 : 0

  role       = aws_iam_role.risk_scorer[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ============================================================================
# CloudWatch Log Group
# ============================================================================

resource "aws_cloudwatch_log_group" "risk_scorer" {
  count = var.enable_lambda_target ? 1 : 0

  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 7

  tags = local.common_tags
}

# ============================================================================
# Lambda Function
# ============================================================================

resource "aws_lambda_function" "risk_scorer" {
  count = var.enable_lambda_target ? 1 : 0

  function_name = local.lambda_function_name
  role          = aws_iam_role.risk_scorer[0].arn
  handler       = "scorer.handler"
  runtime       = "python3.11"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.risk_scorer[0].output_path
  source_code_hash = data.archive_file.risk_scorer[0].output_base64sha256

  description = "MarketPulse risk profile scorer for AgentCore Gateway Lambda target"

  environment {
    variables = {
      LOG_LEVEL = "INFO"
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.risk_scorer_basic,
    aws_cloudwatch_log_group.risk_scorer,
  ]
}

# ============================================================================
# Lambda Permission for Gateway Invocation
# ============================================================================

# Allow the AgentCore Gateway service to invoke this Lambda function.
# Only created when both Gateway and Lambda target are enabled (Lambda target
# is not meaningful without a Gateway to route through).
resource "aws_lambda_permission" "allow_gateway" {
  count = (var.enable_gateway && var.enable_lambda_target) ? 1 : 0

  statement_id  = "AllowAgentCoreGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.risk_scorer[0].function_name
  principal     = "bedrock-agentcore.amazonaws.com"
  source_arn    = aws_iam_role.gateway[0].arn
}

# ============================================================================
# Gateway IAM Policy Update - Allow Lambda Invocation
# ============================================================================

# Grant the Gateway execution role permission to call the risk scorer Lambda
resource "aws_iam_role_policy" "gateway_lambda_access" {
  count = (var.enable_gateway && var.enable_lambda_target) ? 1 : 0

  name = "${local.name_prefix}-gateway-lambda-access"
  role = aws_iam_role.gateway[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.risk_scorer[0].arn
        ]
      }
    ]
  })
}

# ============================================================================
# Lambda Gateway Target Registration
# ============================================================================

# Use null_resource + AWS CLI to register the Lambda target, consistent with
# how the Gateway and HTTP target are managed in gateway.tf.
resource "null_resource" "lambda_gateway_target" {
  count = (var.enable_gateway && var.enable_lambda_target) ? 1 : 0

  triggers = {
    lambda_arn   = aws_lambda_function.risk_scorer[0].arn
    gateway_id   = local.gateway_id
    project_name = var.project_name
    environment  = var.environment
    region       = var.aws_region
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Read Gateway ID from the file written by the gateway null_resource
      if [ ! -f "${path.module}/.gateway_id" ]; then
        echo "Error: Gateway ID file not found. Deploy the Gateway first."
        exit 1
      fi

      GATEWAY_ID=$(cat ${path.module}/.gateway_id)

      if [ -z "$GATEWAY_ID" ] || [ "$GATEWAY_ID" = "pending" ] || [ "$GATEWAY_ID" = "None" ]; then
        echo "Error: Gateway ID is not available. Deploy the Gateway first."
        exit 1
      fi

      echo "Registering Lambda target with Gateway: $GATEWAY_ID"

      # Check if the target already exists
      EXISTING_ID=$(aws bedrock-agentcore-control list-gateway-targets \
        --gateway-identifier "$GATEWAY_ID" \
        --region ${var.aws_region} \
        --query 'items[?name==`assess-risk-profile`].targetId | [0]' \
        --output text 2>/dev/null || echo "")

      if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "None" ]; then
        TARGET_ID="$EXISTING_ID"
        echo "Lambda target already exists: $TARGET_ID"
      else
        echo "Creating Lambda Gateway target..."
        TARGET_OUTPUT=$(aws bedrock-agentcore-control create-gateway-target \
          --gateway-identifier "$GATEWAY_ID" \
          --name "assess-risk-profile" \
          --target-configuration '{
            "mcp": {
              "lambda": {
                "lambdaArn": "${aws_lambda_function.risk_scorer[0].arn}",
                "toolSchema": {
                  "inlinePayload": [
                    {
                      "name": "assess_client_suitability",
                      "description": "Assesses whether a stock is suitable for a clients risk profile. Returns a suitability label and plain-language reasoning for the advisor.",
                      "inputSchema": {
                        "type": "object",
                        "properties": {
                          "ticker": {
                            "type": "string",
                            "description": "Stock ticker symbol e.g. AAPL MSFT TSLA"
                          },
                          "risk_profile": {
                            "type": "string",
                            "description": "Client risk profile: conservative, moderate, or aggressive"
                          }
                        },
                        "required": ["ticker", "risk_profile"]
                      }
                    }
                  ]
                }
              }
            }
          }' \
          --credential-provider-configurations '[{"credentialProviderType": "GATEWAY_IAM_ROLE"}]' \
          --region ${var.aws_region} 2>&1)

        TARGET_EXIT=$?

        if [ $TARGET_EXIT -ne 0 ]; then
          if echo "$TARGET_OUTPUT" | grep -q "already exists\|ConflictException"; then
            TARGET_ID=$(aws bedrock-agentcore-control list-gateway-targets \
              --gateway-identifier "$GATEWAY_ID" \
              --region ${var.aws_region} \
              --query 'items[?name==`assess-risk-profile`].targetId | [0]' \
              --output text)
          else
            echo "Error creating Lambda target: $TARGET_OUTPUT"
            exit 1
          fi
        else
          TARGET_ID=$(echo "$TARGET_OUTPUT" | jq -r '.targetId // .target.targetId // empty')
        fi
      fi

      if [ -z "$TARGET_ID" ] || [ "$TARGET_ID" = "None" ]; then
        echo "Error: Failed to get valid Lambda Target ID"
        exit 1
      fi

      # Persist for destroy and outputs
      aws ssm put-parameter \
        --name "/${var.project_name}/${var.environment}/lambda-target-id" \
        --value "$TARGET_ID" \
        --type String \
        --overwrite \
        --region ${var.aws_region} > /dev/null

      echo "Lambda Gateway target registered: $TARGET_ID"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      TARGET_ID=$(aws ssm get-parameter \
        --name "/${self.triggers.project_name}/${self.triggers.environment}/lambda-target-id" \
        --query 'Parameter.Value' \
        --output text \
        --region ${self.triggers.region} 2>/dev/null || echo "")

      if [ -n "$TARGET_ID" ] && [ "$TARGET_ID" != "None" ]; then
        echo "Removing Lambda Gateway target: $TARGET_ID"
        aws bedrock-agentcore-control delete-gateway-target \
          --gateway-identifier "${self.triggers.gateway_id}" \
          --target-id "$TARGET_ID" \
          --region ${self.triggers.region} || true
      fi

      aws ssm delete-parameter \
        --name "/${self.triggers.project_name}/${self.triggers.environment}/lambda-target-id" \
        --region ${self.triggers.region} 2>/dev/null || true
    EOT
  }

  depends_on = [
    null_resource.gateway,
    aws_lambda_function.risk_scorer,
    aws_lambda_permission.allow_gateway,
    aws_iam_role_policy.gateway_lambda_access,
  ]
}
