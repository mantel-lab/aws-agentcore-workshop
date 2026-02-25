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
    command     = "${path.module}/../scripts/build-mcp.sh"
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
# Cognito User Pool - MCP Server Inbound JWT Auth
# ============================================================================
#
# MCP Gateway targets MUST use OAuth - GATEWAY_IAM_ROLE is not supported.
# The Runtime validates incoming JWT Bearer tokens against this Cognito pool.
# The Gateway receives OAuth tokens via the AgentCore Identity credential
# provider and sends them as Bearer headers when calling the MCP Runtime.

resource "aws_cognito_user_pool" "mcp_server" {
  count = var.enable_mcp_target ? 1 : 0

  name = "${local.mcp_server_name}-auth"

  # Machine-to-machine only - no user sign-ups
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  tags = local.common_tags
}

# Domain provides the Cognito token endpoint used by the credential provider
resource "aws_cognito_user_pool_domain" "mcp_server" {
  count = var.enable_mcp_target ? 1 : 0

  # Must be globally unique; combine name prefix with last 8 digits of account ID
  domain       = "${local.name_prefix}-mcp-${substr(local.account_id, -8, 8)}"
  user_pool_id = aws_cognito_user_pool.mcp_server[0].id
}

# Resource server defines the OAuth scopes the M2M client can request
resource "aws_cognito_resource_server" "mcp_server" {
  count = var.enable_mcp_target ? 1 : 0

  identifier   = "mcp-runtime-server"
  name         = "MCP Runtime Server"
  user_pool_id = aws_cognito_user_pool.mcp_server[0].id

  scope {
    scope_name        = "invoke"
    scope_description = "Invoke MCP server tools via AgentCore Gateway"
  }
}

# M2M app client: Gateway uses client credentials to obtain Bearer tokens
resource "aws_cognito_user_pool_client" "gateway_m2m" {
  count = var.enable_mcp_target ? 1 : 0

  name         = "${local.mcp_server_name}-gateway-client"
  user_pool_id = aws_cognito_user_pool.mcp_server[0].id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_scopes                 = ["mcp-runtime-server/invoke"]

  depends_on = [aws_cognito_resource_server.mcp_server]
}

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

  # Inbound JWT auth: Runtime validates Bearer tokens issued by the Cognito
  # pool before passing requests to the FastMCP container.
  authorizer_configuration = {
    custom_jwt_authorizer = {
      allowed_clients = [aws_cognito_user_pool_client.gateway_m2m[0].id]
      discovery_url   = "https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.mcp_server[0].id}/.well-known/openid-configuration"
      allowed_scopes  = ["mcp-runtime-server/invoke"]
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role.mcp_runtime,
    aws_iam_role_policy.mcp_ecr_access,
    aws_iam_role_policy.mcp_logs_access,
    time_sleep.mcp_iam_propagation,
    null_resource.build_mcp_image,
    aws_cognito_user_pool_client.gateway_m2m,
    aws_cognito_user_pool_domain.mcp_server,
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
# Creates an AgentCore Identity credential provider that stores the Cognito
# M2M client credentials. The Gateway uses this to obtain JWT tokens and
# authenticate to the MCP Runtime via Bearer header.

resource "null_resource" "mcp_oauth_credential_provider" {
  count = (var.enable_gateway && var.enable_mcp_target) ? 1 : 0

  triggers = {
    user_pool_id = aws_cognito_user_pool.mcp_server[0].id
    client_id    = aws_cognito_user_pool_client.gateway_m2m[0].id
    region       = var.aws_region
    project_name = var.project_name
    environment  = var.environment
  }

  provisioner "local-exec" {
    command = "${path.module}/../scripts/create-mcp-oauth-provider.sh"
    environment = {
      PROVIDER_NAME     = "${local.mcp_server_name}-oauth-provider"
      DISCOVERY_URL     = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.mcp_server[0].id}/.well-known/openid-configuration"
      MCP_CLIENT_ID     = aws_cognito_user_pool_client.gateway_m2m[0].id
      MCP_CLIENT_SECRET = aws_cognito_user_pool_client.gateway_m2m[0].client_secret
      SSM_PARAM_NAME    = "/${var.project_name}/${var.environment}/mcp-oauth-provider-arn"
      AWS_REGION        = var.aws_region
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      PROVIDER_ARN=$(aws ssm get-parameter \
        --name "/${self.triggers.project_name}/${self.triggers.environment}/mcp-oauth-provider-arn" \
        --query 'Parameter.Value' --output text \
        --region ${self.triggers.region} 2>/dev/null || echo "")

      if [ -n "$PROVIDER_ARN" ] && [ "$PROVIDER_ARN" != "None" ]; then
        echo "Deleting OAuth2 credential provider: $PROVIDER_ARN"
        aws bedrock-agentcore-control delete-oauth2-credential-provider \
          --oauth2-credential-provider-arn "$PROVIDER_ARN" \
          --region ${self.triggers.region} 2>/dev/null || true
      fi

      aws ssm delete-parameter \
        --name "/${self.triggers.project_name}/${self.triggers.environment}/mcp-oauth-provider-arn" \
        --region ${self.triggers.region} 2>/dev/null || true
    EOT
  }

  depends_on = [
    aws_cognito_user_pool.mcp_server,
    aws_cognito_user_pool_client.gateway_m2m,
    aws_cognito_user_pool_domain.mcp_server,
    awscc_bedrockagentcore_runtime_endpoint.mcp,
  ]
}

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
# MCP targets ONLY support OAUTH - the Gateway fetches a JWT from Cognito via
# the AgentCore Identity credential provider and sends it as a Bearer token.
resource "null_resource" "mcp_gateway_target" {
  count = (var.enable_gateway && var.enable_mcp_target) ? 1 : 0

  triggers = {
    mcp_runtime_id    = awscc_bedrockagentcore_runtime.mcp[0].id
    mcp_endpoint      = awscc_bedrockagentcore_runtime_endpoint.mcp[0].name
    gateway_id        = local.gateway_id
    project_name      = var.project_name
    environment       = var.environment
    region            = var.aws_region
    account_id        = local.account_id
    cognito_client_id = aws_cognito_user_pool_client.gateway_m2m[0].id
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

        # Retrieve the AgentCore Identity credential provider ARN created earlier
        OAUTH_PROVIDER_ARN=$(aws ssm get-parameter \
          --name "/${var.project_name}/${var.environment}/mcp-oauth-provider-arn" \
          --query 'Parameter.Value' --output text \
          --region ${var.aws_region})

        if [ -z "$OAUTH_PROVIDER_ARN" ] || [ "$OAUTH_PROVIDER_ARN" = "None" ]; then
          echo "Error: OAuth provider ARN not found in SSM. Run terraform apply again."
          exit 1
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
          --credential-provider-configurations "[{
            \"credentialProviderType\": \"OAUTH\",
            \"credentialProvider\": {
              \"oauthCredentialProvider\": {
                \"providerArn\": \"$OAUTH_PROVIDER_ARN\",
                \"scopes\": [\"mcp-runtime-server/invoke\"]
              }
            }
          }]" \
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

  depends_on = [
    null_resource.gateway,
    awscc_bedrockagentcore_runtime_endpoint.mcp,
    aws_iam_role_policy.gateway_mcp_access,
    null_resource.mcp_oauth_credential_provider,
  ]
}
