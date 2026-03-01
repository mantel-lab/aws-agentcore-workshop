# AWS AgentCore Workshop: MarketPulse - Memory Configuration
# Module 5: AgentCore Memory
#
# This module enables persistent memory for advisor and client context.
# Memory stores both short-term events and long-term user preferences.
# Enable this module by setting enable_memory = true in terraform.tfvars.

# ============================================================================
# AgentCore Memory
# ============================================================================

resource "awscc_bedrockagentcore_memory" "advisor_memory" {
  count = var.enable_memory ? 1 : 0

  name                   = local.memory_name
  description            = "Memory store for MarketPulse advisor and client context"
  event_expiry_duration = 90 # Days until short-term memory events expire

  # Memory strategies - AWS allows one strategy of each type
  # User preference for advisor settings, semantic for client facts
  memory_strategies = [
    {
      user_preference_memory_strategy = {
        name = "AdvisorPreferences"
        namespaces = ["/advisors/{actorId}/preferences/"]
      }
    },
    {
      semantic_memory_strategy = {
        name = "ClientProfiles"
        namespaces = ["/clients/{actorId}/"]
      }
    }
  ]

  tags = local.common_tags
}

# ============================================================================
# IAM Policy for Agent Runtime to Access Memory
# ============================================================================

# Allow agent runtime to read/write to memory when memory is enabled
resource "aws_iam_role_policy" "agent_memory_access" {
  count = var.enable_memory ? 1 : 0

  name = "${local.agent_name}-memory-access"
  role = aws_iam_role.agent_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:InvokeMemory",
          "bedrock-agentcore:GetMemory",
          "bedrock-agentcore:ListMemories",
          "bedrock-agentcore:ListEvents",
          "bedrock-agentcore:GetEvent",
          "bedrock-agentcore:CreateEvent",
          "bedrock-agentcore:DeleteEvent"
        ]
        Resource = [
          awscc_bedrockagentcore_memory.advisor_memory[0].memory_arn
        ]
      }
    ]
  })
}