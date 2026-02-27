# AWS AgentCore Workshop: MarketPulse - Identity Configuration
# Module 6: OAuth 2.0 Identity with Cognito
#
# This module secures the MCP Gateway target with OAuth 2.0 authentication.
# The Gateway obtains JWT Bearer tokens from Cognito via an AgentCore Identity
# credential provider and presents them when calling the MCP Runtime endpoint.
# The MCP Runtime validates tokens against the Cognito user pool before
# forwarding requests to the FastMCP container.
#
# Feature flag: enable_identity
# Prerequisites: enable_gateway = true, enable_mcp_target = true

# ============================================================================
# Cognito User Pool - OAuth Authorisation Server
# ============================================================================
#
# Cognito acts as the OAuth 2.0 authorisation server, issuing JWT access tokens
# for machine-to-machine (M2M) authentication between Gateway and MCP server.

resource "aws_cognito_user_pool" "mcp_server" {
  count = (var.enable_mcp_target && var.enable_identity) ? 1 : 0

  name = "${local.mcp_server_name}-auth"

  # Machine-to-machine only - no user sign-ups or interactive authentication
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  tags = local.common_tags
}

# ============================================================================
# Cognito User Pool Domain
# ============================================================================
#
# Domain provides the OAuth token endpoint (/.well-known/openid-configuration)
# used by the AgentCore Identity credential provider to discover the token URL
# and public keys for JWT verification.

resource "aws_cognito_user_pool_domain" "mcp_server" {
  count = (var.enable_mcp_target && var.enable_identity) ? 1 : 0

  # Must be globally unique; combine name prefix with last 8 digits of account ID
  domain       = "${local.name_prefix}-mcp-${substr(local.account_id, -8, 8)}"
  user_pool_id = aws_cognito_user_pool.mcp_server[0].id
}

# ============================================================================
# Cognito Resource Server
# ============================================================================
#
# Resource server defines custom OAuth scopes that clients can request.
# Scopes provide fine-grained access control - in this case, the "invoke" scope
# grants permission to call MCP server tools via the Gateway.

resource "aws_cognito_resource_server" "mcp_server" {
  count = (var.enable_mcp_target && var.enable_identity) ? 1 : 0

  identifier   = "mcp-runtime-server"
  name         = "MCP Runtime Server"
  user_pool_id = aws_cognito_user_pool.mcp_server[0].id

  scope {
    scope_name        = "invoke"
    scope_description = "Invoke MCP server tools via AgentCore Gateway"
  }
}

# ============================================================================
# Cognito User Pool Client - Gateway M2M Client
# ============================================================================
#
# M2M app client for Gateway to obtain Bearer tokens via client_credentials flow.
# The Gateway presents client_id + client_secret to Cognito and receives a JWT.
# This JWT is then sent as a Bearer token when calling the MCP Runtime endpoint.

resource "aws_cognito_user_pool_client" "gateway_m2m" {
  count = (var.enable_mcp_target && var.enable_identity) ? 1 : 0

  name         = "${local.mcp_server_name}-gateway-client"
  user_pool_id = aws_cognito_user_pool.mcp_server[0].id

  # Generate client secret for confidential client authentication
  generate_secret = true

  # Enable client credentials flow for M2M authentication
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]

  # Request the custom scope defined in the resource server
  allowed_oauth_scopes = ["mcp-runtime-server/invoke"]

  depends_on = [aws_cognito_resource_server.mcp_server]
}

# ============================================================================
# AgentCore Identity - OAuth2 Credential Provider
# ============================================================================
#
# Creates an AgentCore Identity credential provider that stores the Cognito
# M2M client credentials. The Gateway uses this to obtain JWT tokens and
# authenticate to the MCP Runtime via Bearer header.
#
# The provider ARN is stored in SSM Parameter Store so the Gateway target
# registration can reference it.

resource "null_resource" "mcp_oauth_credential_provider" {
  count = (var.enable_gateway && var.enable_mcp_target && var.enable_identity) ? 1 : 0

  triggers = {
    user_pool_id  = aws_cognito_user_pool.mcp_server[0].id
    client_id     = aws_cognito_user_pool_client.gateway_m2m[0].id
    region        = var.aws_region
    project_name  = var.project_name
    environment   = var.environment
  }

  provisioner "local-exec" {
    command     = "${path.module}/../scripts/create-mcp-oauth-provider.sh"
    working_dir = path.module
    environment = {
      PROVIDER_NAME     = "${var.project_name}-${var.environment}-mcp-oauth"
      DISCOVERY_URL     = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.mcp_server[0].id}/.well-known/openid-configuration"
      MCP_CLIENT_ID     = aws_cognito_user_pool_client.gateway_m2m[0].id
      MCP_CLIENT_SECRET = aws_cognito_user_pool_client.gateway_m2m[0].client_secret
      SSM_PARAM_NAME    = "/${var.project_name}/${var.environment}/mcp-oauth-provider-arn"
      AWS_REGION        = var.aws_region
    }
  }

  depends_on = [
    aws_cognito_user_pool_domain.mcp_server,
    aws_cognito_user_pool_client.gateway_m2m,
  ]
}

# ============================================================================
# Outputs
# ============================================================================

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID for MCP server authentication"
  value       = var.enable_identity && var.enable_mcp_target ? aws_cognito_user_pool.mcp_server[0].id : null
}

output "cognito_user_pool_domain" {
  description = "Cognito User Pool domain for token endpoint"
  value       = var.enable_identity && var.enable_mcp_target ? aws_cognito_user_pool_domain.mcp_server[0].domain : null
}

output "cognito_client_id" {
  description = "Cognito M2M client ID for Gateway authentication"
  value       = var.enable_identity && var.enable_mcp_target ? aws_cognito_user_pool_client.gateway_m2m[0].id : null
  sensitive   = true
}

output "oauth_discovery_url" {
  description = "OpenID Connect discovery URL for the Cognito user pool"
  value       = var.enable_identity && var.enable_mcp_target ? "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.mcp_server[0].id}/.well-known/openid-configuration" : null
}

output "mcp_authentication_enabled" {
  description = "Whether OAuth 2.0 authentication is enabled for the MCP server"
  value       = var.enable_identity && var.enable_mcp_target
}