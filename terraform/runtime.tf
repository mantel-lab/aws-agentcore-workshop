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
      environment = [
        {
          name  = "BEDROCK_MODEL_ID"
          value = var.bedrock_model_id
        }
      ]
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy.agent_bedrock_access,
    aws_iam_role_policy.agent_ecr_access,
    aws_iam_role_policy.agent_logs_access
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
