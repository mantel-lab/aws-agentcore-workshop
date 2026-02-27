# AWS AgentCore Workshop: MarketPulse - MCP Server Configuration
# Module 4: MCP Server Gateway Target
#
# Deploys a FastMCP server (wrapping the Nager.Date API) to AgentCore Runtime
# and registers it as a Gateway MCP_SERVER target.
# Enable this module by setting: enable_mcp_target = true

# ============================================================================
# ECR Repository for MCP Server Container
# ============================================================================

resource "aws_ecr_repository" "mcp_server" {
  count = var.enable_mcp_target ? 1 : 0

  name                 = local.ecr_mcp_repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "mcp_server" {
  count = var.enable_mcp_target ? 1 : 0

  repository = aws_ecr_repository.mcp_server[0].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ============================================================================
# MCP Server Container Build and Push
# ============================================================================

# Build and push the MCP server container before the Runtime is created.
# This ensures AgentCore can pull the image on first deployment.
resource "null_resource" "build_mcp_image" {
  count = var.enable_mcp_target ? 1 : 0

  triggers = {
    ecr_repository_url = aws_ecr_repository.mcp_server[0].repository_url
    server_code_hash   = filemd5("${path.module}/../mcp-server/server.py")
    dockerfile_hash    = filemd5("${path.module}/../mcp-server/Dockerfile")
    requirements_hash  = filemd5("${path.module}/../mcp-server/requirements.txt")
  }

  provisioner "local-exec" {
    command     = "${path.module}/../scripts/build-container.sh mcp"
    working_dir = path.module
    environment = {
      ECR_REPO_URL = aws_ecr_repository.mcp_server[0].repository_url
      AWS_REGION   = local.region
    }
  }

  depends_on = [
    aws_ecr_repository.mcp_server,
    aws_ecr_lifecycle_policy.mcp_server,
  ]
}

# ============================================================================
# Cognito Resources for OAuth Authentication
# ============================================================================
#
# OAuth 2.0 authentication resources are defined in identity.tf and conditionally
# created when enable_identity = true. This allows Module 4 to deploy the MCP
# server without authentication, and Module 6 to add OAuth security on top.
#
# See identity.tf for:
# - aws_cognito_user_pool.mcp_server
# - aws_cognito_user_pool_domain.mcp_server
# - aws_cognito_resource_server.mcp_server
# - aws_cognito_user_pool_client.gateway_m2m
# - null_resource.mcp_oauth_credential_provider

# ============================================================================
# IAM Role for MCP Server Runtime
# ============================================================================

resource "aws_iam_role" "mcp_runtime" {
  count = var.enable_mcp_target ? 1 : 0

  name = "${local.mcp_server_name}-runtime-role"

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

# ECR image pull access for the MCP server runtime
resource "aws_iam_role_policy" "mcp_ecr_access" {
  count = var.enable_mcp_target ? 1 : 0

  name = "${local.mcp_server_name}-ecr-access"
  role = aws_iam_role.mcp_runtime[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
        ]
        Resource = [aws_ecr_repository.mcp_server[0].arn]
      },
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Logs access for MCP server runtime
resource "aws_iam_role_policy" "mcp_logs_access" {
  count = var.enable_mcp_target ? 1 : 0

  name = "${local.mcp_server_name}-logs-access"
  role = aws_iam_role.mcp_runtime[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "*"
      }
    ]
  })
}

# Wait for MCP IAM role and policies to propagate before creating the Runtime
resource "time_sleep" "mcp_iam_propagation" {
  count = var.enable_mcp_target ? 1 : 0

  create_duration = "10s"

  depends_on = [
    aws_iam_role.mcp_runtime,
    aws_iam_role_policy.mcp_ecr_access,
    aws_iam_role_policy.mcp_logs_access,
  ]
}

# ============================================================================
# AgentCore Runtime for MCP Server
# ============================================================================

resource "awscc_bedrockagentcore_runtime" "mcp" {
  count = var.enable_mcp_target ? 1 : 0

  # Runtime name must match ^[a-zA-Z][a-zA-Z0-9_]{0,47}$ (no hyphens)
  agent_runtime_name = local.mcp_server_runtime_name
  role_arn           = aws_iam_role.mcp_runtime[0].arn

  # PUBLIC mode for workshop simplicity
  network_configuration = {
    network_mode       = "PUBLIC"
    subnet_ids         = []
    security_group_ids = []
  }

  agent_runtime_artifact = {
    container_configuration = {
      container_uri = "${aws_ecr_repository.mcp_server[0].repository_url}:latest"
    }
  }

  environment_variables = {
    LOG_LEVEL = "INFO"
  }

  # Inbound JWT auth: Conditionally validate Bearer tokens when enable_identity = true
  # Module 4: No authorizer (omit field - open access for workshop simplicity)
  # Module 6: JWT authorizer validates tokens from Cognito before forwarding to FastMCP
  authorizer_configuration = var.enable_identity ? {
    custom_jwt_authorizer = {
      allowed_clients = [aws_cognito_user_pool_client.gateway_m2m[0].id]
      discovery_url   = "https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.mcp_server[0].id}/.well-known/openid-configuration"
      allowed_scopes  = ["mcp-runtime-server/invoke"]
    }
  } : null

  tags = local.common_tags

  # Note: When enable_identity=false, Cognito resources have count=0 and are
  # automatically skipped by Terraform. No need for dynamic depends_on.
  depends_on = [
    aws_iam_role.mcp_runtime,
    aws_iam_role_policy.mcp_ecr_access,
    aws_iam_role_policy.mcp_logs_access,
    time_sleep.mcp_iam_propagation,
    null_resource.build_mcp_image,
    aws_cognito_user_pool.mcp_server,
    aws_cognito_user_pool_client.gateway_m2m,
    aws_cognito_user_pool_domain.mcp_server,
    aws_cognito_resource_server.mcp_server,
  ]
}

# ============================================================================
# MCP Server Runtime Endpoint
# ============================================================================

resource "awscc_bedrockagentcore_runtime_endpoint" "mcp" {
  count = var.enable_mcp_target ? 1 : 0

  # Endpoint name must also follow ^[a-zA-Z][a-zA-Z0-9_]{0,47}$
  name             = local.mcp_endpoint_name
  agent_runtime_id = awscc_bedrockagentcore_runtime.mcp[0].id

  tags = local.common_tags
}

# ============================================================================
# AgentCore Identity - OAuth2 Credential Provider
# ============================================================================
#
# OAuth 2.0 credential provider is defined in identity.tf and conditionally
# created when enable_identity = true.  See identity.tf for:
# - null_resource.mcp_oauth_credential_provider

# ============================================================================
# Gateway IAM Policy Update - Allow MCP Runtime Invocation
# ============================================================================

# Grant the Gateway execution role permission to invoke the MCP server Runtime.
# With JWT inbound auth, the Runtime accepts Bearer tokens; the Gateway still
# requires InvokeAgentRuntime to reach the bedrock-agentcore endpoint.
resource "aws_iam_role_policy" "gateway_mcp_access" {
  count = (var.enable_gateway && var.enable_mcp_target) ? 1 : 0

  name = "${local.name_prefix}-gateway-mcp-access"
  role = aws_iam_role.gateway[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:InvokeAgentRuntime",
        ]
        Resource = [
          "arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:runtime/${awscc_bedrockagentcore_runtime.mcp[0].id}",
        ]
      }
    ]
  })
}

# ============================================================================
# Gateway MCP_SERVER Target Registration
# ============================================================================

# The Gateway needs the MCP server's invocation URL to discover and call tools.
# URL format: https://bedrock-agentcore.{region}.amazonaws.com/runtimes/{url-encoded-arn}/invocations?qualifier={endpoint-name}
#
# Module 4 (enable_identity=false): GATEWAY_IAM_ROLE credential type (no authentication)
# Module 6 (enable_identity=true): OAUTH credential type with JWT Bearer tokens
resource "null_resource" "mcp_gateway_target" {
  count = (var.enable_gateway && var.enable_mcp_target) ? 1 : 0

  triggers = {
    mcp_runtime_id     = awscc_bedrockagentcore_runtime.mcp[0].id
    mcp_endpoint       = awscc_bedrockagentcore_runtime_endpoint.mcp[0].name
    gateway_id         = local.gateway_id
    project_name       = var.project_name
    environment        = var.environment
    region             = var.aws_region
    account_id         = local.account_id
    enable_identity    = var.enable_identity
    cognito_client_id  = var.enable_identity ? aws_cognito_user_pool_client.gateway_m2m[0].id : ""
  }

  provisioner "local-exec" {
    command = <<-EOT
      if [ ! -f "${path.module}/.gateway_id" ]; then
        echo "Error: Gateway ID file not found. Deploy the Gateway first."
        exit 1
      fi

      GATEWAY_ID=$(cat ${path.module}/.gateway_id)

      if [ -z "$GATEWAY_ID" ] || [ "$GATEWAY_ID" = "pending" ] || [ "$GATEWAY_ID" = "None" ]; then
        echo "Error: Gateway ID is not valid. Deploy the Gateway first."
        exit 1
      fi

      # Construct the MCP Runtime invocation URL.
      # The ARN is URL-encoded so it can be embedded in the path component.
      MCP_RUNTIME_ARN="arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:runtime/${awscc_bedrockagentcore_runtime.mcp[0].id}"
      MCP_RUNTIME_ARN_ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$MCP_RUNTIME_ARN")
      MCP_ENDPOINT_NAME="${awscc_bedrockagentcore_runtime_endpoint.mcp[0].name}"
      MCP_ENDPOINT_URL="https://bedrock-agentcore.${var.aws_region}.amazonaws.com/runtimes/$MCP_RUNTIME_ARN_ENCODED/invocations?qualifier=$MCP_ENDPOINT_NAME"

      echo "Registering MCP server target with Gateway: $GATEWAY_ID"
      echo "MCP Endpoint URL: $MCP_ENDPOINT_URL"

      # Check whether the target already exists
      EXISTING_ID=$(aws bedrock-agentcore-control list-gateway-targets \
        --gateway-identifier "$GATEWAY_ID" \
        --region ${var.aws_region} \
        --query 'items[?name==`market-calendar`].targetId | [0]' \
        --output text 2>/dev/null || echo "")

      if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "None" ]; then
        TARGET_ID="$EXISTING_ID"
        echo "MCP target already exists: $TARGET_ID"
      else
        echo "Creating MCP_SERVER gateway target..."

        # Module 6: OAuth authentication (requires AgentCore Identity credential provider)
        # Module 4: IAM role authentication (simpler, no separate OAuth setup)
        if [ "${var.enable_identity}" = "true" ]; then
          echo "Using OAuth 2.0 authentication (enable_identity=true)"
          
          # Retrieve the AgentCore Identity credential provider ARN created in identity.tf
          OAUTH_PROVIDER_ARN=$(aws ssm get-parameter \
            --name "/${var.project_name}/${var.environment}/mcp-oauth-provider-arn" \
            --query 'Parameter.Value' --output text \
            --region ${var.aws_region} 2>/dev/null || echo "")

          if [ -z "$OAUTH_PROVIDER_ARN" ] || [ "$OAUTH_PROVIDER_ARN" = "None" ]; then
            echo "Error: OAuth provider ARN not found in SSM. Deploy identity.tf first (enable_identity=true)."
            exit 1
          fi

          CRED_PROVIDER_JSON="[{
            \"credentialProviderType\": \"OAUTH\",
            \"credentialProvider\": {
              \"oauthCredentialProvider\": {
                \"providerArn\": \"$OAUTH_PROVIDER_ARN\",
                \"scopes\": [\"mcp-runtime-server/invoke\"]
              }
            }
          }]"
        else
          echo "Using Gateway IAM role authentication (enable_identity=false)"
          
          CRED_PROVIDER_JSON="[{
            \"credentialProviderType\": \"GATEWAY_IAM_ROLE\"
          }]"
        fi

        set +e
        TARGET_OUTPUT=$(aws bedrock-agentcore-control create-gateway-target \
          --gateway-identifier "$GATEWAY_ID" \
          --name "market-calendar" \
          --target-configuration "{
            \"mcp\": {
              \"mcpServer\": {
                \"endpoint\": \"$MCP_ENDPOINT_URL\"
              }
            }
          }" \
          --credential-provider-configurations "$CRED_PROVIDER_JSON" \
          --region ${var.aws_region} 2>&1)
        TARGET_EXIT=$?
        set -e

        if [ $TARGET_EXIT -ne 0 ]; then
          if echo "$TARGET_OUTPUT" | grep -q "already exists\|ConflictException"; then
            TARGET_ID=$(aws bedrock-agentcore-control list-gateway-targets \
              --gateway-identifier "$GATEWAY_ID" \
              --region ${var.aws_region} \
              --query 'items[?name==`market-calendar`].targetId | [0]' \
              --output text)
          else
            echo "Error creating MCP target: $TARGET_OUTPUT"
            exit 1
          fi
        else
          TARGET_ID=$(echo "$TARGET_OUTPUT" | jq -r '.targetId // .target.targetId // empty')
        fi
      fi

      if [ -z "$TARGET_ID" ] || [ "$TARGET_ID" = "None" ]; then
        echo "Error: Failed to get valid MCP Target ID"
        exit 1
      fi

      # Trigger MCP tool discovery. AgentCore calls the server's tools/list endpoint
      # and builds a searchable catalogue for agents to query.
      echo "Synchronising MCP tool catalogue..."
      aws bedrock-agentcore-control synchronize-gateway-targets \
        --gateway-identifier "$GATEWAY_ID" \
        --target-id-list "$TARGET_ID" \
        --region ${var.aws_region} 2>/dev/null \
        && echo "Synchronisation triggered (runs asynchronously)" \
        || echo "Synchronisation request skipped - tools will sync on first Gateway request"

      aws ssm put-parameter \
        --name "/${var.project_name}/${var.environment}/mcp-target-id" \
        --value "$TARGET_ID" \
        --type String \
        --overwrite \
        --region ${var.aws_region} > /dev/null

      echo "MCP Gateway target registered: $TARGET_ID"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      TARGET_ID=$(aws ssm get-parameter \
        --name "/${self.triggers.project_name}/${self.triggers.environment}/mcp-target-id" \
        --query 'Parameter.Value' \
        --output text \
        --region ${self.triggers.region} 2>/dev/null || echo "")

      if [ -n "$TARGET_ID" ] && [ "$TARGET_ID" != "None" ]; then
        echo "Removing MCP Gateway target: $TARGET_ID"
        aws bedrock-agentcore-control delete-gateway-target \
          --gateway-identifier "${self.triggers.gateway_id}" \
          --target-id "$TARGET_ID" \
          --region ${self.triggers.region} || true
      fi

      aws ssm delete-parameter \
        --name "/${self.triggers.project_name}/${self.triggers.environment}/mcp-target-id" \
        --region ${self.triggers.region} 2>/dev/null || true
    EOT
  }

  # Note: When enable_identity=false, Cognito resources have count=0 and
  # null_resource.mcp_oauth_credential_provider doesn't exist. Terraform skips
  # non-existent dependencies automatically.
  depends_on = [
    null_resource.gateway,
    awscc_bedrockagentcore_runtime_endpoint.mcp,
    aws_iam_role_policy.gateway_mcp_access,
    null_resource.mcp_oauth_credential_provider,
  ]
}
