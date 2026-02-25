#!/usr/bin/env bash
set -euo pipefail

# AWS AgentCore Workshop: MarketPulse - MCP OAuth2 Credential Provider Setup
#
# Creates an AgentCore Identity OAuth2 credential provider backed by Cognito.
# The Gateway uses this provider to get JWT Bearer tokens when calling the
# MCP server Runtime endpoint.
#
# Called by null_resource.mcp_oauth_credential_provider in mcp.tf.
# All inputs are provided as environment variables by Terraform local-exec.
#
# Required env vars (injected by Terraform):
#   PROVIDER_NAME     - name for the AgentCore credential provider
#   DISCOVERY_URL     - Cognito .well-known/openid-configuration URL
#   MCP_CLIENT_ID     - Cognito M2M app client ID
#   MCP_CLIENT_SECRET - Cognito M2M app client secret
#   SSM_PARAM_NAME    - SSM parameter path to store the provider ARN
#   AWS_REGION        - AWS region

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Setting up MCP OAuth2 credential provider${NC}"
echo "Provider name: ${PROVIDER_NAME}"
echo "Discovery URL: ${DISCOVERY_URL}"
echo "Client ID:     ${MCP_CLIENT_ID}"
echo ""

# Check if a provider ARN was stored from a previous apply
EXISTING_ARN=$(aws ssm get-parameter \
  --name "${SSM_PARAM_NAME}" \
  --query 'Parameter.Value' \
  --output text \
  --region "${AWS_REGION}" 2>/dev/null || echo "")

if [ -n "${EXISTING_ARN}" ] && [ "${EXISTING_ARN}" != "None" ]; then
  echo -e "${YELLOW}OAuth2 credential provider already registered: ${EXISTING_ARN}${NC}"
  echo "Skipping creation. Delete the SSM parameter to force recreation."
  exit 0
fi

# Create the AgentCore Identity OAuth2 credential provider
echo -e "${YELLOW}Creating AgentCore Identity OAuth2 credential provider...${NC}"

set +e
PROVIDER_OUTPUT=$(aws bedrock-agentcore-control create-oauth2-credential-provider \
  --name "${PROVIDER_NAME}" \
  --credential-provider-vendor "CustomOauth2" \
  --oauth2-provider-config-input "{
    \"customOauth2ProviderConfig\": {
      \"oauthDiscovery\": {
        \"discoveryUrl\": \"${DISCOVERY_URL}\"
      },
      \"clientId\": \"${MCP_CLIENT_ID}\",
      \"clientSecret\": \"${MCP_CLIENT_SECRET}\"
    }
  }" \
  --region "${AWS_REGION}" 2>&1)
PROVIDER_EXIT=$?
set -e

if [ ${PROVIDER_EXIT} -ne 0 ]; then
  if echo "${PROVIDER_OUTPUT}" | grep -q "ConflictException\|already exists"; then
    echo -e "${YELLOW}Provider already exists - this can happen if a previous apply failed partway through.${NC}"
    echo "The provider exists in AgentCore but was not recorded in SSM."
    echo "Manual step required: find the provider ARN and set SSM parameter '${SSM_PARAM_NAME}'."
    echo "  aws bedrock-agentcore-control list-oauth2-credential-providers --region ${AWS_REGION}"
    exit 1
  else
    echo -e "${RED}Error creating OAuth2 credential provider:${NC}"
    echo "${PROVIDER_OUTPUT}"
    exit 1
  fi
fi

PROVIDER_ARN=$(echo "${PROVIDER_OUTPUT}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('credentialProviderArn', ''))" 2>/dev/null || \
              echo "${PROVIDER_OUTPUT}" | grep -o '"credentialProviderArn":"[^"]*"' | cut -d'"' -f4)

if [ -z "${PROVIDER_ARN}" ]; then
  echo -e "${RED}Error: Could not extract credential provider ARN from response:${NC}"
  echo "${PROVIDER_OUTPUT}"
  exit 1
fi

echo -e "${GREEN}Created OAuth2 credential provider: ${PROVIDER_ARN}${NC}"

# Store in SSM for the gateway target registration step
aws ssm put-parameter \
  --name "${SSM_PARAM_NAME}" \
  --value "${PROVIDER_ARN}" \
  --type "String" \
  --overwrite \
  --region "${AWS_REGION}" > /dev/null

echo -e "${GREEN}Provider ARN stored in SSM: ${SSM_PARAM_NAME}${NC}"
