#!/usr/bin/env bash
set -euo pipefail

# AWS AgentCore Workshop: MarketPulse - Agent Build Script
# This script builds the MarketPulse agent Docker image and pushes it to ECR.

# Colour codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AGENT_DIR="${PROJECT_ROOT}/agent"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

# Parse command line arguments
REGION="${1:-ap-southeast-2}"

echo -e "${GREEN}Building MarketPulse Agent Container${NC}"
echo "Region: ${REGION}"
echo ""

# Check if agent directory exists
if [[ ! -d "${AGENT_DIR}" ]]; then
    echo -e "${RED}Error: Agent directory not found at ${AGENT_DIR}${NC}"
    exit 1
fi

# Check if Dockerfile exists
if [[ ! -f "${AGENT_DIR}/Dockerfile" ]]; then
    echo -e "${RED}Error: Dockerfile not found in ${AGENT_DIR}${NC}"
    exit 1
fi

# Get ECR repository details from Terraform
echo -e "${YELLOW}Getting ECR repository details from Terraform...${NC}"
cd "${TERRAFORM_DIR}"
REPOSITORY_NAME=$(terraform output -raw ecr_repository_name 2>/dev/null)
ECR_REPO_URL=$(terraform output -raw ecr_repository_url 2>/dev/null)

if [[ -z "${REPOSITORY_NAME}" ]] || [[ -z "${ECR_REPO_URL}" ]]; then
    echo -e "${RED}Error: Failed to get ECR repository details from Terraform${NC}"
    echo "Make sure you've run 'terraform apply' first"
    exit 1
fi
echo "Repository Name: ${REPOSITORY_NAME}"
echo "Repository URL: ${ECR_REPO_URL}"
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
cd "${AGENT_DIR}"
docker build --platform linux/arm64 -t "${REPOSITORY_NAME}:latest" .
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Error: Docker build failed${NC}"
    exit 1
fi
echo -e "${GREEN}Docker image built successfully${NC}"
echo ""

# Tag image for ECR
echo -e "${YELLOW}Tagging image for ECR...${NC}"
docker tag "${REPOSITORY_NAME}:latest" "${ECR_REPO_URL}:latest"
echo -e "${GREEN}Image tagged: ${ECR_REPO_URL}:latest${NC}"
echo ""

# Push image to ECR
echo -e "${YELLOW}Pushing image to ECR...${NC}"
docker push "${ECR_REPO_URL}:latest"
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
echo "Image URI: ${ECR_REPO_URL}:latest"
echo "Image Digest: ${IMAGE_DIGEST}"
echo ""
echo "Next steps:"
echo "1. Run 'terraform apply' to deploy the agent runtime"
echo "2. Test the agent with scripts/test-agent.py"