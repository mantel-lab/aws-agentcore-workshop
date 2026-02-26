# AWS AgentCore Workshop: MarketPulse - Gateway Configuration
# Module 2: AgentCore Gateway + HTTP Target (via OpenAPI)
#
# This module deploys AgentCore Gateway and configures an HTTP target for
# Finnhub stock price API using OpenAPI specification.

# ============================================================================
# IAM Role for Gateway
# ============================================================================

resource "aws_iam_role" "gateway" {
  count = var.enable_gateway ? 1 : 0

  name = "${local.name_prefix}-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "bedrock-agentcore.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Policy allowing Gateway to invoke targets and access credentials
resource "aws_iam_role_policy" "gateway_execution" {
  count = var.enable_gateway ? 1 : 0

  name = "${local.name_prefix}-gateway-execution"
  role = aws_iam_role.gateway[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:InvokeGatewayTarget",
          "bedrock-agentcore:GetGatewayTarget",
          "bedrock-agentcore:ListGatewayTargets"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = var.enable_http_target ? [aws_secretsmanager_secret.finnhub_api_key[0].arn] : []
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = var.enable_http_target ? ["${aws_s3_bucket.openapi_specs[0].arn}/*"] : []
      }
    ]
  })
}

# ============================================================================
# S3 Bucket for OpenAPI Specifications
# ============================================================================

resource "aws_s3_bucket" "openapi_specs" {
  count = var.enable_http_target ? 1 : 0

  bucket = "${local.name_prefix}-openapi-specs"

  tags = local.common_tags
}

# Block public access to OpenAPI specs bucket
resource "aws_s3_bucket_public_access_block" "openapi_specs" {
  count = var.enable_http_target ? 1 : 0

  bucket = aws_s3_bucket.openapi_specs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# Finnhub OpenAPI Specification
# ============================================================================

# OpenAPI spec for Finnhub quote endpoint
resource "aws_s3_object" "finnhub_openapi_spec" {
  count = var.enable_http_target ? 1 : 0

  bucket       = aws_s3_bucket.openapi_specs[0].id
  key          = "finnhub-api-spec.json"
  content_type = "application/json"

  content = jsonencode({
    openapi = "3.0.0"
    info = {
      title       = "Finnhub Stock Quote API"
      description = "Real-time stock price data from Finnhub"
      version     = "1.0.0"
    }
    servers = [
      {
        url = "https://finnhub.io/api/v1"
      }
    ]
    paths = {
      "/quote" = {
        get = {
          operationId = "get_stock_price"
          summary     = "Get stock quote"
          description = "Retrieves current stock price and trading data for a ticker symbol"
          parameters = [
            {
              name        = "symbol"
              in          = "query"
              required    = true
              description = "Stock ticker symbol (e.g., AAPL, MSFT, TSLA)"
              schema = {
                type = "string"
              }
            }
          ]
          responses = {
            "200" = {
              description = "Successful response with stock quote data"
              content = {
                "application/json" = {
                  schema = {
                    type = "object"
                    properties = {
                      c = {
                        type        = "number"
                        description = "Current price"
                      }
                      d = {
                        type        = "number"
                        description = "Change"
                      }
                      dp = {
                        type        = "number"
                        description = "Percent change"
                      }
                      h = {
                        type        = "number"
                        description = "High price of the day"
                      }
                      l = {
                        type        = "number"
                        description = "Low price of the day"
                      }
                      o = {
                        type        = "number"
                        description = "Open price"
                      }
                      pc = {
                        type        = "number"
                        description = "Previous close price"
                      }
                      t = {
                        type        = "integer"
                        description = "Unix timestamp"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  })

  tags = local.common_tags
}

# ============================================================================
# Secrets Manager for Finnhub API Key
# ============================================================================

resource "aws_secretsmanager_secret" "finnhub_api_key" {
  count = var.enable_http_target ? 1 : 0

  name                    = "${local.name_prefix}-finnhub-api-key"
  description             = "Finnhub API key for stock price data"
  recovery_window_in_days = 0 # Force immediate deletion on destroy

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "finnhub_api_key" {
  count = var.enable_http_target ? 1 : 0

  secret_id     = aws_secretsmanager_secret.finnhub_api_key[0].id
  secret_string = var.finnhub_api_key
}

# ============================================================================
# AgentCore Gateway
# ============================================================================

# Note: Using AWS CLI-based approach as AWSCC provider may not have full Gateway support yet
# This is a workshop-appropriate implementation that uses null_resource to create Gateway via AWS CLI

resource "null_resource" "gateway" {
  count = var.enable_gateway ? 1 : 0

  # Trigger recreation when role changes
  triggers = {
    role_arn     = aws_iam_role.gateway[0].arn
    runtime_id   = awscc_bedrockagentcore_runtime.agent.id
    project_name = var.project_name
    environment  = var.environment
    region       = var.aws_region
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Check if Gateway already exists
      EXISTING_GATEWAY=$(aws bedrock-agentcore-control list-gateways \
        --region ${var.aws_region} \
        --query "items[?name=='${local.name_prefix}-gateway'].gatewayId | [0]" \
        --output text 2>&1)
      
      # If gateway exists, use existing ID
      if [ -n "$EXISTING_GATEWAY" ] && [ "$EXISTING_GATEWAY" != "None" ] && [ "$EXISTING_GATEWAY" != "null" ]; then
        GATEWAY_ID="$EXISTING_GATEWAY"
        echo "Using existing Gateway: $GATEWAY_ID"
      else
        # Create new Gateway using AWS CLI with error capture
        CREATE_OUTPUT=$(aws bedrock-agentcore-control create-gateway \
          --name "${local.name_prefix}-gateway" \
          --role-arn "${aws_iam_role.gateway[0].arn}" \
          --protocol-type MCP \
          --authorizer-type AWS_IAM \
          --region ${var.aws_region} 2>&1)
        
        CREATE_EXIT=$?
        
        # Check if gateway creation succeeded
        if [ $CREATE_EXIT -ne 0 ]; then
          echo "Error creating Gateway:"
          echo "$CREATE_OUTPUT"
          exit 1
        fi
        
        # Extract Gateway ID from output
        GATEWAY_ID=$(echo "$CREATE_OUTPUT" | jq -r '.gateway.gatewayId // empty')
        
        # Validate Gateway ID
        if [ -z "$GATEWAY_ID" ] || [ "$GATEWAY_ID" == "null" ] || [ "$GATEWAY_ID" == "None" ]; then
          echo "Error: Failed to extract Gateway ID from response:"
          echo "$CREATE_OUTPUT"
          exit 1
        fi
        
        echo "Gateway created successfully: $GATEWAY_ID"
      fi
      
      # Save Gateway ID to SSM Parameter for reference
      aws ssm put-parameter \
        --name "/${var.project_name}/${var.environment}/gateway-id" \
        --value "$GATEWAY_ID" \
        --type String \
        --overwrite \
        --region ${var.aws_region} > /dev/null
      
      # Save Gateway ID to local file for Terraform to reference
      printf "%s" "$GATEWAY_ID" > ${path.module}/.gateway_id
      echo "Gateway ID saved: $GATEWAY_ID"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # Try to retrieve Gateway ID from local file first, then SSM
      GATEWAY_ID=""
      if [ -f "${path.module}/.gateway_id" ]; then
        GATEWAY_ID=$(cat ${path.module}/.gateway_id)
      else
        GATEWAY_ID=$(aws ssm get-parameter \
          --name "/${self.triggers.project_name}/${self.triggers.environment}/gateway-id" \
          --query 'Parameter.Value' \
          --output text \
          --region ${self.triggers.region} 2>/dev/null || echo "")
      fi
      
      # Delete Gateway if ID exists
      if [ -n "$GATEWAY_ID" ] && [ "$GATEWAY_ID" != "None" ]; then
        echo "Deleting Gateway: $GATEWAY_ID"
        aws bedrock-agentcore-control delete-gateway \
          --gateway-identifier "$GATEWAY_ID" \
          --region ${self.triggers.region} || true
      else
        echo "No Gateway ID found for cleanup"
      fi
      
      # Clean up SSM parameter and local file
      aws ssm delete-parameter \
        --name "/${self.triggers.project_name}/${self.triggers.environment}/gateway-id" \
        --region ${self.triggers.region} 2>/dev/null || true
      
      rm -f ${path.module}/.gateway_id
    EOT
  }

  depends_on = [
    aws_iam_role.gateway,
    aws_iam_role_policy.gateway_execution
  ]
}

# Local file to store Gateway ID (created by null_resource)
# This avoids SSM data source read timing issues during first apply
# Using try() to handle case where file doesn't exist yet (first plan)
locals {
  gateway_id = var.enable_gateway ? try(file("${path.module}/.gateway_id"), "pending") : null
}

# ============================================================================
# OpenAPI HTTP Target for Finnhub
# ============================================================================

resource "null_resource" "finnhub_http_target" {
  count = var.enable_http_target ? 1 : 0

  # Trigger recreation when dependencies change
  triggers = {
    gateway_id        = local.gateway_id
    openapi_spec_etag = aws_s3_object.finnhub_openapi_spec[0].etag
    secret_arn        = aws_secretsmanager_secret.finnhub_api_key[0].arn
    project_name      = var.project_name
    environment       = var.environment
    region            = var.aws_region
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Retrieve API key from Secrets Manager
      API_KEY=$(aws secretsmanager get-secret-value \
        --secret-id "${aws_secretsmanager_secret.finnhub_api_key[0].id}" \
        --region ${var.aws_region} \
        --query 'SecretString' \
        --output text)
      
      # Read Gateway ID from file (created by gateway resource)
      if [ ! -f "${path.module}/.gateway_id" ]; then
        echo "Error: Gateway ID file not found. Gateway may not have been created yet."
        exit 1
      fi
      
      GATEWAY_ID=$(cat ${path.module}/.gateway_id)
      
      # Validate Gateway ID
      if [ -z "$GATEWAY_ID" ] || [ "$GATEWAY_ID" == "pending" ] || [ "$GATEWAY_ID" == "None" ]; then
        echo "Error: Gateway ID is not available. Gateway may not have been created yet."
        exit 1
      fi
      
      echo "Using Gateway ID: $GATEWAY_ID"
      
      # Check if credential provider already exists, otherwise create it
      CREDENTIAL_ARN=$(aws bedrock-agentcore-control list-api-key-credential-providers \
        --region ${var.aws_region} \
        --query 'credentialProviders[?name==`finnhub-api-key-${var.environment}`].credentialProviderArn | [0]' \
        --output text 2>/dev/null || echo "")
      
      if [ -z "$CREDENTIAL_ARN" ] || [ "$CREDENTIAL_ARN" == "None" ]; then
        echo "Creating new credential provider..."
        CREDENTIAL_ARN=$(aws bedrock-agentcore-control create-api-key-credential-provider \
          --name "finnhub-api-key-${var.environment}" \
          --api-key "$API_KEY" \
          --region ${var.aws_region} \
          --query 'credentialProviderArn' \
          --output text)
      else
        echo "Using existing credential provider: $CREDENTIAL_ARN"
      fi
      
      # Create Gateway target with OpenAPI spec
      echo "Creating Gateway target..."
      
      # Run command and capture output and exit code separately
      set +e  # Temporarily disable exit on error
      TARGET_OUTPUT=$(aws bedrock-agentcore-control create-gateway-target \
        --gateway-identifier "$GATEWAY_ID" \
        --name "get-stock-price" \
        --target-configuration '{
          "mcp": {
            "openApiSchema": {
              "s3": {
                "uri": "s3://${aws_s3_bucket.openapi_specs[0].id}/${aws_s3_object.finnhub_openapi_spec[0].key}",
                "bucketOwnerAccountId": "${local.account_id}"
              }
            }
          }
        }' \
        --credential-provider-configurations "[{
          \"credentialProviderType\": \"API_KEY\",
          \"credentialProvider\": {
            \"apiKeyCredentialProvider\": {
              \"providerArn\": \"$CREDENTIAL_ARN\",
              \"credentialLocation\": \"QUERY_PARAMETER\",
              \"credentialParameterName\": \"token\"
            }
          }
        }]" \
        --region ${var.aws_region} 2>&1)
      TARGET_EXIT=$?
      set -e  # Re-enable exit on error
      
      # Check if target creation was successful
      if [ $TARGET_EXIT -ne 0 ]; then
        # If target already exists, try to get its ID
        if echo "$TARGET_OUTPUT" | grep -q "already exists\|ConflictException"; then
          echo "Target already exists, retrieving existing target ID..."
          TARGET_ID=$(aws bedrock-agentcore-control list-gateway-targets \
            --gateway-identifier "$GATEWAY_ID" \
            --region ${var.aws_region} \
            --query 'items[?name==`get-stock-price`].targetId | [0]' \
            --output text)
        else
          echo "Error creating target: $TARGET_OUTPUT"
          exit 1
        fi
      else
        # Extract target ID from successful creation
        TARGET_ID=$(echo "$TARGET_OUTPUT" | jq -r '.targetId // .target.targetId // empty')
      fi
      
      # Validate Target ID before saving
      if [ -z "$TARGET_ID" ] || [ "$TARGET_ID" == "None" ]; then
        echo "Error: Failed to get valid Target ID"
        exit 1
      fi
      
      # Save Target ID to SSM Parameter
      aws ssm put-parameter \
        --name "/${var.project_name}/${var.environment}/finnhub-target-id" \
        --value "$TARGET_ID" \
        --type String \
        --overwrite \
        --region ${var.aws_region}
      
      echo "Finnhub Target ID: $TARGET_ID"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # Retrieve Target ID from SSM
      TARGET_ID=$(aws ssm get-parameter \
        --name "/${self.triggers.project_name}/${self.triggers.environment}/finnhub-target-id" \
        --query 'Parameter.Value' \
        --output text \
        --region ${self.triggers.region} 2>/dev/null || echo "")
      
      # Delete Target if ID exists
      if [ -n "$TARGET_ID" ] && [ "$TARGET_ID" != "None" ]; then
        echo "Deleting Gateway Target: $TARGET_ID from Gateway: ${self.triggers.gateway_id}"
        aws bedrock-agentcore-control delete-gateway-target \
          --gateway-identifier "${self.triggers.gateway_id}" \
          --target-id "$TARGET_ID" \
          --region ${self.triggers.region} || true
      else
        echo "No Target ID found for cleanup"
      fi
      
      # Clean up SSM parameter
      aws ssm delete-parameter \
        --name "/${self.triggers.project_name}/${self.triggers.environment}/finnhub-target-id" \
        --region ${self.triggers.region} 2>/dev/null || true
    EOT
  }

  depends_on = [
    null_resource.gateway,
    aws_s3_object.finnhub_openapi_spec,
    aws_secretsmanager_secret_version.finnhub_api_key
  ]
}
