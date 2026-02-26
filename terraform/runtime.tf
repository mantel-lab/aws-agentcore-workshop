# AWS AgentCore Workshop: MarketPulse - Runtime Configuration
# Module 1: AgentCore Runtime
#
# This module deploys the MarketPulse agent to AgentCore Runtime.
# The agent is packaged as a Docker container and stored in ECR.
# Runtime is always deployed (no feature flag) as it's the foundation for all modules.

# ============================================================================
# ECR Repository for Agent Container
# ============================================================================

resource "aws_ecr_repository" "agent" {
  name                 = local.ecr_repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

# ECR lifecycle policy to manage image retention
resource "aws_ecr_lifecycle_policy" "agent" {
  repository = aws_ecr_repository.agent.name

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
# Docker Image Build and Push
# ============================================================================

# Build and push the agent container image to ECR
resource "null_resource" "build_agent_image" {
  # Trigger rebuild when ECR repository changes or agent code changes
  triggers = {
    ecr_repository_url = aws_ecr_repository.agent.repository_url
    agent_code_hash    = filemd5("${path.module}/../agent/app.py")
    dockerfile_hash    = filemd5("${path.module}/../agent/Dockerfile")
    requirements_hash  = filemd5("${path.module}/../agent/requirements.txt")
  }

  provisioner "local-exec" {
    command     = "${path.module}/../scripts/build-container.sh agent"
    working_dir = path.module
    environment = {
      ECR_REPO_URL = aws_ecr_repository.agent.repository_url
      AWS_REGION   = local.region
    }
  }

  depends_on = [
    aws_ecr_repository.agent,
    aws_ecr_lifecycle_policy.agent
  ]
}

# ============================================================================
# IAM Role for AgentCore Runtime
# ============================================================================

resource "aws_iam_role" "agent_runtime" {
  name = "${local.agent_name}-runtime-role"

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

# Policy for Bedrock model invocation
resource "aws_iam_role_policy" "agent_bedrock_access" {
  name = "${local.agent_name}-bedrock-access"
  role = aws_iam_role.agent_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_model_id}"
        ]
      }
    ]
  })
}

# Policy for ECR image access
resource "aws_iam_role_policy" "agent_ecr_access" {
  name = "${local.agent_name}-ecr-access"
  role = aws_iam_role.agent_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = [
          aws_ecr_repository.agent.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy for CloudWatch Logs access
resource "aws_iam_role_policy" "agent_logs_access" {
  name = "${local.agent_name}-logs-access"
  role = aws_iam_role.agent_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy for Gateway invocation (Module 2+)
resource "aws_iam_role_policy" "agent_gateway_access" {
  count = var.enable_gateway ? 1 : 0

  name = "${local.agent_name}-gateway-access"
  role = aws_iam_role.agent_runtime.id

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
      }
    ]
  })
}

# Allow time for IAM role and policies to propagate
resource "time_sleep" "iam_propagation" {
  create_duration = "10s"

  depends_on = [
    aws_iam_role.agent_runtime,
    aws_iam_role_policy.agent_bedrock_access,
    aws_iam_role_policy.agent_ecr_access,
    aws_iam_role_policy.agent_logs_access
  ]
}

# ============================================================================
# AgentCore Runtime
# ============================================================================

resource "awscc_bedrockagentcore_runtime" "agent" {
  agent_runtime_name = local.agent_name
  role_arn           = aws_iam_role.agent_runtime.arn

  # Network configuration - using PUBLIC mode for workshop simplicity
  network_configuration = {
    network_mode       = "PUBLIC"
    subnet_ids         = []
    security_group_ids = []
  }

  # Container image from ECR
  agent_runtime_artifact = {
    container_configuration = {
      container_uri = "${aws_ecr_repository.agent.repository_url}:latest"
    }
  }

  # Environment variables - must be at top level, not in container_configuration
  environment_variables = {
    BEDROCK_MODEL_ID     = var.bedrock_model_id
    ENABLE_GATEWAY       = var.enable_gateway ? "true" : "false"
    ENABLE_LAMBDA_TARGET = var.enable_lambda_target ? "true" : "false"
    ENABLE_MCP_TARGET    = var.enable_mcp_target ? "true" : "false"
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role.agent_runtime,
    aws_iam_role_policy.agent_bedrock_access,
    aws_iam_role_policy.agent_ecr_access,
    aws_iam_role_policy.agent_logs_access,
    aws_iam_role_policy.agent_gateway_access,
    time_sleep.iam_propagation,
    null_resource.build_agent_image
  ]
}

# ============================================================================
# Runtime Endpoint
# ============================================================================

resource "awscc_bedrockagentcore_runtime_endpoint" "agent" {
  name             = local.runtime_endpoint_name
  agent_runtime_id = awscc_bedrockagentcore_runtime.agent.id

  tags = local.common_tags
}
