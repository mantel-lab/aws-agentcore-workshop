#!/usr/bin/env bash
set -euo pipefail

# AWS AgentCore Workshop: MarketPulse - MCP Server Build Script
# Builds the Market Calendar MCP server Docker image and pushes it to ECR.

# Colour codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MCP_DIR="${PROJECT_ROOT}/mcp-server"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

echo -e "${GREEN}Building MarketPulse MCP Server Container${NC}"
echo ""

# Check required directories and files
if [[ ! -d "${MCP_DIR}" ]]; then
    echo -e "${RED}Error: MCP server directory not found at ${MCP_DIR}${NC}"
    exit 1
fi

if [[ ! -f "${MCP_DIR}/Dockerfile" ]]; then
    echo -e "${RED}Error: Dockerfile not found in ${MCP_DIR}${NC}"
    exit 1
fi

# Get ECR repository details - injected by Terraform local-exec, or read from state for manual runs
echo -e "${YELLOW}Getting ECR repository details...${NC}"
REGION="${AWS_REGION:-${1:-ap-southeast-2}}"

if [[ -n "${ECR_REPO_URL:-}" ]]; then
    ECR_MCP_REPO_URL="${ECR_REPO_URL}"
else
    # Fallback for manual invocation outside of terraform apply
    cd "${TERRAFORM_DIR}"
    ECR_MCP_REPO_URL=$(terraform output -raw ecr_mcp_repository_url 2>/dev/null)
fi

if [[ -z "${ECR_MCP_REPO_URL}" ]]; then
    echo -e "${RED}Error: ECR repository URL not found.${NC}"
    echo "Run from terraform (or run 'terraform apply' with enable_mcp_target=true first)"
    exit 1
fi

# Derive repository name from URL (everything after the last /)
REPOSITORY_NAME="${ECR_MCP_REPO_URL##*/}"
echo "Region:          ${REGION}"
echo "Repository Name: ${REPOSITORY_NAME}"
echo "Repository URL:  ${ECR_MCP_REPO_URL}"
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
echo -e "${YELLOW}Building MCP server Docker image...${NC}"
cd "${MCP_DIR}"
docker build --platform linux/arm64 -t "${REPOSITORY_NAME}:latest" .
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Error: Docker build failed${NC}"
    exit 1
fi
echo -e "${GREEN}Docker image built successfully${NC}"
echo ""

# Tag image for ECR
echo -e "${YELLOW}Tagging image for ECR...${NC}"
docker tag "${REPOSITORY_NAME}:latest" "${ECR_MCP_REPO_URL}:latest"
echo -e "${GREEN}Image tagged: ${ECR_MCP_REPO_URL}:latest${NC}"
echo ""

# Push image to ECR
echo -e "${YELLOW}Pushing image to ECR...${NC}"
docker push "${ECR_MCP_REPO_URL}:latest"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Error: Failed to push image to ECR${NC}"
    exit 1
fi
echo -e "${GREEN}Image pushed successfully${NC}"
echo ""

# Get image digest for confirmation
IMAGE_DIGEST=$(aws ecr describe-images \
    --repository-name "${REPOSITORY_NAME}" \
    --region "${REGION}" \
    --query 'imageDetails[0].imageDigest' \
    --output text 2>/dev/null || echo "unavailable")

echo -e "${GREEN}=== Build Complete ===${NC}"
echo "Image URI: ${ECR_MCP_REPO_URL}:latest"
echo "Image Digest: ${IMAGE_DIGEST}"
echo ""
echo "Next steps:"
echo "1. Run 'terraform apply' if not already done (Runtime will pull the new image)"
echo "2. Test the agent with scripts/test-calendar.py"
