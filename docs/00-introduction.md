# Module 0: Introduction to AWS Bedrock AgentCore

**Duration:** 15 minutes reading  
**Prerequisites:** None

## What is AWS Bedrock AgentCore?

AWS Bedrock AgentCore is a fully managed platform for building, deploying, and operating AI agents at scale. It provides the infrastructure, integration capabilities, and operational tooling needed to run production AI agents in enterprise environments.

Think of AgentCore as AWS Lambda for AI agents: you write your agent code, package it in a container, and AgentCore handles the scaling, security, and operational concerns.

## Why AgentCore Matters for FSI

Financial services institutions face unique challenges when deploying AI:

1. **Compliance Requirements** - Every AI decision must be auditable and explainable
2. **Security Standards** - Service-to-service communication must be authenticated
3. **Integration Complexity** - Agents need access to internal systems and external data
4. **Operational Maturity** - Production agents require monitoring, logging, and debugging

AgentCore addresses each of these concerns through purpose-built components that work together as a platform.

## Platform Components

AgentCore consists of seven integrated components. This workshop uses all of them:

### 1. AgentCore Runtime

**What it is:** A managed container runtime for hosting AI agents.

**Why it matters:** Instead of managing EC2 instances, ECS clusters, or Kubernetes, you deploy a container and AgentCore handles scaling, health checks, and infrastructure.

**In this workshop:** You'll deploy the MarketPulse agent to Runtime in Module 1.

**FSI relevance:** Standardised hosting reduces operational burden and ensures consistent security posture across all agents.

### 2. AgentCore Gateway

**What it is:** A managed integration layer that exposes external APIs, Lambda functions, and MCP servers as tools that agents can call.

**Why it matters:** Agents need to interact with external systems (stock APIs, internal databases, compliance services). Gateway provides a standardised interface for these integrations, handling authentication, rate limiting, and request routing.

**In this workshop:** You'll configure three different target types:
- HTTP target for stock prices (Module 2)
- Lambda target for risk scoring (Module 3)
- MCP target for market calendars (Module 4)

**FSI relevance:** Gateway ensures all external calls are centrally managed, logged, and subject to access controls. This is critical for regulatory oversight.

### 3. AgentCore Memory

**What it is:** A managed service that gives agents the ability to remember past interactions.

**Why it matters:** Stateful conversations improve user experience and reduce cognitive load. A financial advisor shouldn't need to repeat client details in every session.

**In this workshop:** You'll enable memory so MarketPulse remembers client risk profiles across sessions (Module 5).

**FSI relevance:** Memory must respect data boundaries. AgentCore Memory provides namespace isolation, ensuring advisor A cannot access advisor B's client data.

### 4. AgentCore Identity

**What it is:** OAuth 2.0 client credentials management for service-to-service authentication.

**Why it matters:** In a regulated environment, no service should accept unauthenticated requests. Identity ensures every caller is identified and authorised.

**In this workshop:** You'll secure the MCP server so only authenticated agents can access it (Module 6).

**FSI relevance:** Demonstrates how to enforce authentication policies that meet compliance requirements.

### 5. AgentCore Observability

**What it is:** Distributed tracing for agents, showing exactly what the agent did, in what order, and how long each step took.

**Why it matters:** When an agent makes a recommendation, you need to understand its reasoning. Observability provides an audit trail of every tool call, input, and output.

**In this workshop:** You'll instrument MarketPulse and inspect a complete trace showing all tool calls (Module 7).

**FSI relevance:** Audit trails are mandatory for regulated AI systems. Observability provides the foundation for explainability and compliance.

### 6. AgentCore Versioning

**What it is:** Immutable versioning of agent deployments with rollback capability.

**Why it matters:** When you update an agent, you need to be able to roll back if issues arise.

**In this workshop:** Not covered (extension activity).

### 7. AgentCore Orchestration

**What it is:** Multi-agent coordination and workflow management.

**Why it matters:** Complex tasks often require multiple specialised agents working together.

**In this workshop:** Not covered (extension activity).

## Agent Framework: Strands

AgentCore is runtime-agnostic - you can deploy agents built with any framework that outputs a container. This workshop uses **Strands**, a Python framework specifically designed for AgentCore.

**Key Strands concepts:**

```python
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from strands import Agent
from strands.models import BedrockModel

# Initialise AgentCore app
app = BedrockAgentCoreApp()

# Create agent with model and system prompt
agent = Agent(
    model=BedrockModel(model_id="anthropic.claude-sonnet-4-5-20250929-v1:0"),
    tools=[],  # Tools added via Gateway in later modules
    system_prompt="You are a financial advisor assistant..."
)

# Define entrypoint function
@app.entrypoint
def marketpulse_agent(payload):
    user_input = payload.get("prompt")
    response = agent(user_input)
    return response.message['content'][0]['text']

if __name__ == "__main__":
    app.run()
```

Strands handles:
- Prompt construction with system prompts
- Model integration with Bedrock
- Response parsing
- Agent execution flow

You write business logic, Strands handles the agent mechanics. Tools are added via Gateway, not directly in agent code (you'll see this in Modules 2-4).

## Workshop Architecture Evolution

Each module adds one component to the architecture:

**Module 1: Runtime**
```
[Advisor] → [MarketPulse Agent]
```

**Module 2: Gateway + HTTP Target**
```
[Advisor] → [Agent] → [Gateway] → [Finnhub API]
```

**Module 3: + Lambda Target**
```
                     ┌→ [HTTP: Finnhub]
[Advisor] → [Agent] → [Gateway] ┤
                     └→ [Lambda: Risk Scorer]
```

**Module 4: + MCP Target**
```
                     ┌→ [HTTP: Finnhub]
[Advisor] → [Agent] → [Gateway] ┼→ [Lambda: Risk Scorer]
                     └→ [MCP: Market Calendar]
```

**Module 5: + Memory**
```
[Advisor] → [Agent] → [Gateway] → [Targets]
              ↕
           [Memory]
```

**Module 6: + Identity**
```
[Advisor] → [Agent] → [Gateway] → [Targets]
              ↕           ↓
           [Memory]   [Identity]
```

**Module 7: + Observability**
```
[Advisor] → [Agent] → [Gateway] → [Targets]
              ↕           ↓
           [Memory]   [Identity]
              ↓
        [Observability]
```

## Key Concepts

### 1. Tools vs Targets

**Tool:** What the agent sees. A function signature with a description.

```python
# Agent's view
get_stock_price(ticker: str) -> dict
"""Get the current price for a stock ticker"""
```

**Target:** Where the request actually goes. Could be an HTTP API, Lambda function, or MCP server.

Gateway bridges the gap: agents call tools, Gateway routes to targets.

### 2. Containerisation

AgentCore requires containers:
- Agent code → Docker image → ECR → Runtime
- MCP server code → Docker image → ECR → Runtime

This ensures environment consistency and supports any programming language.

### 3. Feature Flags

This workshop uses Terraform feature flags to enable components progressively:

```hcl
variable "enable_gateway" { default = false }
```

Set to `true`, run `terraform apply`, and the component deploys. This keeps the learning focused: one concept at a time.

### 4. Idempotency

AgentCore operations are idempotent: running `terraform apply` multiple times with the same configuration produces the same result. This is safe to do and often necessary (e.g., after container rebuilds).

## Workshop Workflow

Each module follows this pattern:

1. **Read** the module documentation
2. **Understand** the AgentCore component and its FSI relevance
3. **Enable** the feature flag in `terraform/variables.tf`
4. **Run** `terraform apply` to deploy
5. **Test** the new functionality with a script
6. **Inspect** the AWS console to verify deployment
7. **Discuss** with your workshop cohort

## Common Terminology

| Term | Definition |
|------|------------|
| **Agent** | An AI system that can perceive its environment, make decisions, and take actions |
| **Tool** | A function an agent can call to interact with external systems |
| **Target** | The actual endpoint (HTTP API, Lambda, MCP server) that implements a tool |
| **Runtime** | The managed service that hosts agent containers |
| **Gateway** | The integration layer that routes tool calls to targets |
| **Memory** | The service that stores conversation history and context |
| **Span** | A single unit of work in a distributed trace (e.g., one tool call) |
| **Trace** | A complete request flow showing all spans from start to finish |

## FSI Context: Why Financial Services?

This workshop uses a financial services scenario for several reasons:

1. **Familiarity** - Stock prices, risk profiles, and market calendars are concepts every FSI engineer recognises immediately
2. **Compliance Complexity** - Financial services face stringent regulatory requirements, making it an ideal proving ground for AgentCore's compliance features
3. **Integration Patterns** - FSI systems commonly integrate external market data with internal risk models, mirroring the Gateway's multi-target capability
4. **Audit Requirements** - Every recommendation must be explainable, which maps directly to Observability
5. **Security Posture** - Authenticated service-to-service communication is mandatory, demonstrating Identity

## Before You Begin

Make sure you have:

- [ ] AWS account with Bedrock access
- [ ] Claude 3 Sonnet model access enabled
- [ ] Terraform >= 1.0.7 installed
- [ ] Python 3.11+ installed
- [ ] Docker installed and running
- [ ] AWS CLI configured (`aws configure`)
- [ ] Finnhub API key (free registration)

## What You'll Build

By the end of this workshop, you'll have deployed:

- **1 AI agent** (MarketPulse) responding to advisor queries
- **3 Gateway targets** (HTTP, Lambda, MCP) providing different data sources
- **1 MCP server** wrapping a public holidays API
- **1 Lambda function** scoring client risk profiles
- **Memory** persisting advisor and client context
- **OAuth 2.0** authentication protecting the MCP endpoint
- **Distributed tracing** showing complete request flows

And you'll understand:

- How each AgentCore component addresses real FSI requirements
- When to use HTTP vs Lambda vs MCP targets
- How to instrument agents for compliance and debugging
- Why this architecture pattern is valuable for regulated industries

## Next Steps

Start with [Module 1: AgentCore Runtime](01-runtime.md) to deploy your first agent.

---

**Questions to Consider:**

1. How does your organisation currently host AI/ML workloads? What operational challenges do you face?
2. Where do you see the biggest benefit of managed infrastructure like AgentCore?
3. What compliance or audit requirements does your team need to satisfy?
4. How do you currently trace requests across distributed systems?

These questions will help you connect workshop concepts to your day-to-day work.