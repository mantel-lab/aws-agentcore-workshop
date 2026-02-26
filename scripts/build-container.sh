#!/usr/bin/env bash
set -euo pipefail

# AWS AgentCore Workshop: Container Build Script
# Unified build script for both agent and MCP server containers.
#
# Usage:
#   build-container.sh agent     [region]
#   build-container.sh mcp       [region]

# Colour codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

# Check arguments
if [[ $# -lt 1 ]]; then
    echo -e "${RED}Error: Missing container type argument${NC}"
    echo "Usage: $0 <agent|mcp> [region]"
    exit 1
fi

CONTAINER_TYPE="$1"
REGION="${2:-${AWS_REGION:-ap-southeast-2}}"

# Validate container type
if [[ "$CONTAINER_TYPE" != "agent" ]] && [[ "$CONTAINER_TYPE" != "mcp" ]]; then
    echo -e "${RED}Error: Container type must be 'agent' or 'mcp'${NC}"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

# Set container-specific paths
if [[ "$CONTAINER_TYPE" == "agent" ]]; then
    CONTAINER_DIR="${PROJECT_ROOT}/agent"
    DISPLAY_NAME="MarketPulse Agent"
    TF_OUTPUT_VAR="ecr_repository_url"
    ECR_REPO_URL_VAR="${ECR_REPO_URL:-}"
elif [[ "$CONTAINER_TYPE" == "mcp" ]]; then
    CONTAINER_DIR="${PROJECT_ROOT}/mcp-server"
    DISPLAY_NAME="MarketPulse MCP Server"
    TF_OUTPUT_VAR="ecr_mcp_repository_url"
    ECR_REPO_URL_VAR="${ECR_REPO_URL:-}"
fi

echo -e "${GREEN}Building ${DISPLAY_NAME} Container${NC}"
echo ""

# Check if container directory exists
if [[ ! -d "${CONTAINER_DIR}" ]]; then
    echo -e "${RED}Error: Container directory not found at ${CONTAINER_DIR}${NC}"
    exit 1
fi

# Check if Dockerfile exists
if [[ ! -f "${CONTAINER_DIR}/Dockerfile" ]]; then
    echo -e "${RED}Error: Dockerfile not found in ${CONTAINER_DIR}${NC}"
    exit 1
fi

# Get ECR repository details - injected by Terraform local-exec, or read from state for manual runs
echo -e "${YELLOW}Getting ECR repository details...${NC}"

if [[ -n "${ECR_REPO_URL_VAR}" ]]; then
    REPO_URL="${ECR_REPO_URL_VAR}"
else
    # Fallback for manual invocation outside of terraform apply
    cd "${TERRAFORM_DIR}"
    REPO_URL=$(terraform output -raw "${TF_OUTPUT_VAR}" 2>/dev/null || echo "")
fi

if [[ -z "${REPO_URL}" ]]; then
    echo -e "${RED}Error: ECR repository URL not found.${NC}"
    if [[ "$CONTAINER_TYPE" == "mcp" ]]; then
        echo "Run 'terraform apply' with enable_mcp_target=true first"
    else
        echo "Run 'terraform apply' first"
    fi
    exit 1
fi

# Derive repository name from URL (everything after the last /)
REPOSITORY_NAME="${REPO_URL##*/}"
echo "Region:          ${REGION}"
echo "Repository Name: ${REPOSITORY_NAME}"
echo "Repository URL:  ${REPO_URL}"
echo ""

# Get AWS account ID
echo -e "${YELLOW}Getting AWS account ID...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
    echo -e "${RED}Error: Failed to get AWS account ID. Check AWS credentials.${NC}"
    exit 1
fi
echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
echo ""

# Authenticate Docker to ECR
echo -e "${YELLOW}Authenticating Docker to ECR...${NC}"
aws ecr get-login-password --region "${REGION}" | \
    docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Error: Failed to authenticate Docker to ECR${NC}"
    exit 1
fi
echo -e "${GREEN}Docker authenticated to ECR${NC}"
echo ""

# Build Docker image
echo -e "${YELLOW}Building Docker image...${NC}"
cd "${CONTAINER_DIR}"
docker build --platform linux/arm64 -t "${REPOSITORY_NAME}:latest" .
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Error: Docker build failed${NC}"
    exit 1
fi
echo -e "${GREEN}Docker image built successfully${NC}"
echo ""

# Tag image for ECR
echo -e "${YELLOW}Tagging image for ECR...${NC}"
docker tag "${REPOSITORY_NAME}:latest" "${REPO_URL}:latest"
echo -e "${GREEN}Image tagged: ${REPO_URL}:latest${NC}"
echo ""

# Push image to ECR
echo -e "${YELLOW}Pushing image to ECR...${NC}"
docker push "${REPO_URL}:latest"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Error: Failed to push image to ECR${NC}"
    exit 1
fi
echo -e "${GREEN}Image pushed successfully${NC}"
echo ""

# Get image digest
IMAGE_DIGEST=$(aws ecr describe-images \
    --repository-name "${REPOSITORY_NAME}" \
    --region "${REGION}" \
    --query 'imageDetails[0].imageDigest' \
    --output text)

echo -e "${GREEN}=== Build Complete ===${NC}"
echo "Image URI: ${REPO_URL}:latest"
echo "Image Digest: ${IMAGE_DIGEST}"
echo ""
echo "Next steps:"
if [[ "$CONTAINER_TYPE" == "agent" ]]; then
    echo "1. Run 'terraform apply' to deploy the agent runtime"
    echo "2. Test the agent with scripts/test-agent.py"
elif [[ "$CONTAINER_TYPE" == "mcp" ]]; then
    echo "1. Verify Terraform apply completed successfully"
    echo "2. Test the MCP server with scripts/test-calendar.py"
fi
