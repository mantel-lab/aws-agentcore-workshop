# AWS AgentCore Workshop: MarketPulse Development Plan

## Overview

Build a hands-on workshop that teaches FSI engineers to deploy and operate AI agents using AWS Bedrock AgentCore. The workshop creates "MarketPulse", an investment brief assistant that demonstrates all major AgentCore components through a single Terraform configuration with progressive feature enablement.

**Business Value**: Engineers gain practical experience with AgentCore Runtime, Gateway (HTTP/Lambda/MCP targets), Memory, Identity (OAuth 2.0), and Observability in a coherent FSI context. The repository serves as a reference implementation for future projects.

**Approach**: Single Terraform directory with feature flags. Engineers enable capabilities progressively via variables, keeping focus on AgentCore concepts rather than Terraform state management.

## Current State

**Problems Identified:**
- No existing implementation - starting from scratch
- Workshop document exists but needs translation to working Terraform code
- Engineers need both learning materials AND working infrastructure-as-code

**Technical Context:**
- **IaC**: Terraform with local state file (workshop simplicity)
- **Agent Framework**: Strands Agents SDK (Python)
- **Deployment**: AgentCore Starter Toolkit for containerisation
- **Region**: ap-southeast-2
- **Model**: `anthropic.claude-sonnet-4-5-20250929-v1:0` (configurable)
- **Stock API**: Finnhub (free tier with API key)
- **Holidays API**: Nager.Date (free, no key required)
- **Terraform providers**: AWS >= 4.0.0, AWSCC >= 0.24.0

**Key Constraints from Research:**
- MCP servers MUST use `streamable-http` transport (NOT stdio) when deployed to AgentCore Runtime
- AgentCore Runtime can host both agents AND MCP servers
- Gateway targets support three types: HTTP, Lambda, MCP_SERVER
- Memory supports short-term (STM) and long-term (LTM) with extraction strategies
- Identity uses Cognito User Pool for OAuth 2.0 JWT authentication

**Architecture Decision - Single Directory with Feature Flags:**

Multi-directory approach was rejected because:
1. Gateway is ONE resource with child targets - splitting across directories fights the Terraform resource model
2. Agent code updates span multiple workshop modules but container lives in one place - creates navigation confusion
3. Cross-module state references add complexity that distracts from learning AgentCore
4. Single directory with `count` conditionals matches how teams actually deploy infrastructure

## Requirements

**Functional Requirements:**
1. Workshop MUST deploy a working MarketPulse agent that responds to advisor queries
2. Agent MUST integrate with three Gateway target types: HTTP API, Lambda, MCP Server
3. Memory MUST persist advisor and client context across sessions
4. MCP target MUST be secured with OAuth 2.0 authentication
5. All components MUST be traceable via AgentCore Observability
6. Each feature MUST be deployable via `terraform apply` after toggling a variable
7. Per-module documentation MUST explain concepts for engineers new to AgentCore

**Technical Constraints:**
1. Terraform MUST use local state file for workshop simplicity
2. Agent code MUST use Strands Agents SDK with BedrockAgentCoreApp entrypoint
3. MCP server MUST use `streamable-http` transport, NOT stdio
4. All resources MUST be deployed to ap-southeast-2
5. Model ID MUST be configurable via Terraform variables
6. API keys MUST be stored in AWS Secrets Manager, NOT hardcoded
7. Network mode MUST be PUBLIC for workshop simplicity
8. Terraform state MUST NOT be committed to repository

**Exclusions:**
- VPC networking configuration (use PUBLIC mode)
- Production-grade security hardening beyond workshop requirements
- Multi-region deployment
- Knowledge Base integration (mentioned as extension activity only)

**Prerequisites:**
- AWS account with Bedrock model access enabled for Claude 3 Sonnet
- Terraform >= 1.0.7 installed
- Python 3.11+ installed
- AWS CLI configured with appropriate permissions
- Docker installed (for container builds)
- Finnhub API key (free registration)

## Unknowns & Assumptions

**Unknowns:**
- Exact Finnhub API response format - will need to verify during implementation
- AgentCore Observability console navigation may change - document current UI paths
- Container build time for initial ECR push - may need wait time in documentation

**Assumptions:**
- Workshop participants have basic AWS and Terraform knowledge
- Finnhub free tier rate limits are sufficient for workshop use (60 calls/minute)
- Nager.Date API remains publicly available without authentication
- AgentCore service limits are sufficient for workshop deployments

## Success Criteria

1. All 7 workshop modules deploy successfully via progressive `terraform apply`
2. MarketPulse agent responds correctly to advisor queries exercising all tools
3. Stock price, risk scoring, and market calendar data are correctly retrieved
4. Memory persists client context across separate agent sessions
5. Unauthenticated MCP calls return 401; authenticated calls succeed
6. Full request trace visible in AWS console showing all tool call spans
7. Each module documentation explains the relevant AgentCore concepts
8. Terraform validates and plans without errors (`terraform validate`, `terraform plan`)
9. All Python code passes linting (no syntax errors)
10. Repository includes complete .env.example and terraform.tfvars.example files

---

## Development Plan

### Phase 1: Project Structure and Base Configuration ✓

**Objective**: Establish project structure with single Terraform directory and feature flag variables.

**Status**: COMPLETE

- [x] Create project directory structure:
  ```
  agentcoreworkshop/
  ├── README.md
  ├── .gitignore
  ├── terraform/
  │   ├── main.tf              (providers, backend)
  │   ├── variables.tf         (all variables including feature flags)
  │   ├── outputs.tf           (all outputs)
  │   ├── runtime.tf           (agent runtime - always deployed)
  │   ├── gateway.tf           (gateway + http target)
  │   ├── lambda.tf            (lambda function + gateway target)
  │   ├── mcp.tf               (mcp server runtime + gateway target)
  │   ├── memory.tf            (memory configuration)
  │   ├── identity.tf          (oauth 2.0 configuration)
  │   ├── observability.tf     (tracing configuration)
  │   ├── terraform.tfvars.example
  │   └── locals.tf            (computed values)
  ├── agent/
  │   ├── Dockerfile
  │   ├── requirements.txt
  │   └── app.py
  ├── mcp-server/
  │   ├── Dockerfile
  │   ├── requirements.txt
  │   └── server.py
  ├── lambda/
  │   └── scorer.py
  ├── scripts/
  │   ├── build-agent.sh
  │   ├── build-mcp.sh
  │   └── test-agent.py
  └── docs/
      ├── 01-runtime.md
      ├── 02-gateway-http.md
      ├── 03-gateway-lambda.md
      ├── 04-gateway-mcp.md
      ├── 05-memory.md
      ├── 06-identity.md
      └── 07-observability.md
  ```
- [x] Create main README.md with workshop overview, prerequisites, and feature flag workflow
- [x] Create terraform/variables.tf with feature flags:
  ```hcl
  # Feature flags - enable progressively during workshop
  variable "enable_gateway"        { default = false }
  variable "enable_http_target"    { default = false }
  variable "enable_lambda_target"  { default = false }
  variable "enable_mcp_target"     { default = false }
  variable "enable_memory"         { default = false }
  variable "enable_identity"       { default = false }
  variable "enable_observability"  { default = false }
  ```
- [x] Create terraform/main.tf with AWS provider and local backend configuration
- [x] Create terraform.tfvars.example with configurable variables
- [x] Create .env.example for Finnhub API key
- [x] Create .gitignore excluding .terraform/, *.tfstate*, .env, and sensitive files
- [x] Create terraform/README.md with setup instructions
- [x] All Terraform placeholder files created for future phases (runtime.tf, gateway.tf, lambda.tf, mcp.tf, memory.tf, identity.tf, observability.tf)
- [x] Perform a critical self-review of the structure and fix any issues found
- [x] COMPLETE - Ready for Phase 2

**Notes:**
- Terraform not installed on system - documented in terraform/README.md
- All feature flags default to false for Phase 1
- finnhub_api_key variable made optional with default empty string
- Phase 1 creates NO resources (validated design)
- All files use Australian English spelling as per CLAUDE.md guidelines

### Phase 2: Module 1 - AgentCore Runtime (Deploy & Test)

**Objective**: Deploy the base MarketPulse Strands agent to AgentCore Runtime.

**Status**: COMPLETE

- [x] Create docs/01-runtime.md explaining:
  - AgentCore Runtime concepts (container-based agent hosting)
  - Strands framework basics
  - BedrockAgentCoreApp entrypoint pattern
  - Workshop workflow: modify variables, `terraform apply`
- [x] Create agent/Dockerfile for agent container
- [x] Create agent/requirements.txt (strands-agents, bedrock-agentcore)
- [x] Create agent/app.py with basic Strands agent (no tools yet):
  - BedrockAgentCoreApp entrypoint
  - System prompt for MarketPulse financial advisor assistant
  - Placeholder tool definitions (disabled until features enabled)
- [x] Create terraform/runtime.tf:
  - ECR repository for agent container
  - AgentCore Runtime with container artifact (always deployed)
  - AgentCore Runtime Endpoint
  - IAM role with Bedrock model invocation permissions
- [x] Create scripts/build-agent.sh for Docker build and ECR push
- [x] Create scripts/test-agent.py to send test prompt to deployed agent
- [x] Verify Terraform validates and plans successfully
- [x] Run Docker build and push to ECR
- [x] Deploy with `terraform apply`
- [x] Test deployed agent with test-agent.py - verify agent responds to basic prompt
- [x] Perform a critical self-review of all changes and fix any issues found
- [x] COMPLETE - Ready for Phase 3

**Notes:**
- Agent successfully deployed to AgentCore Runtime
- Container built and pushed to ECR without issues
- Test script executed successfully (exit code 0)
- Runtime endpoint naming validation issue resolved (documented in Working Notes)

### Phase 3: Module 2 - HTTP Gateway Target (Deploy & Test)

**Objective**: Add Finnhub stock price API as HTTP Gateway target.

**Status**: COMPLETE

- [x] Create docs/02-gateway-http.md explaining:
  - AgentCore Gateway concepts
  - HTTP target configuration
  - Tool schema definition for agents
  - How to enable: set `enable_gateway = true` and `enable_http_target = true`
- [x] Create terraform/gateway.tf:
  - AgentCore Gateway (using null_resource with AWS CLI due to limited AWSCC provider support)
  - HTTP target for Finnhub API via OpenAPI specification
  - Tool schema for get_stock_price function
  - Secrets Manager secret for Finnhub API key
  - S3 bucket for OpenAPI specifications
  - IAM role and policies for Gateway execution
- [x] Update agent/app.py to include stock price tool:
  - Add tool definition that declares schema
  - Tool is available when Gateway is enabled
  - AgentCore automatically routes tool calls through Gateway
- [x] Create scripts/test-stock.py to test "What is the current price of AAPL?"
- [x] Verify Terraform validates and plans successfully
- [x] Add IAM permissions for agent runtime to invoke Gateway targets
- [x] Update terraform/README.md with Gateway implementation notes
- [x] Format all Terraform files and verify Python syntax
- [x] COMPLETE - Ready for deployment testing

**Notes:**
- Gateway implementation uses `null_resource` with AWS CLI commands due to limited AWSCC provider support for Gateway resources
- OpenAPI specification approach used for HTTP target (industry standard)
- Circular dependency resolved by simplifying environment variable passing
- Agent tool schema declared statically; routing handled by AgentCore Gateway automatically
- Gateway ID stored in SSM Parameter Store for cross-resource referencing

### Phase 4: Module 3 - Lambda Gateway Target (Deploy & Test)

**Objective**: Deploy risk profile scorer Lambda and register as Gateway target.

- [x] Create docs/03-gateway-lambda.md explaining:
  - Lambda targets in AgentCore Gateway
  - Tool schema for Lambda functions
  - Why risk scoring belongs in Lambda (compliance, versioning, auditability)
  - How to enable: set `enable_lambda_target = true`
- [x] Create lambda/scorer.py with risk profile scoring logic:
  - Input: ticker characteristics + client risk profile
  - Output: suitability label (Suitable, Proceed with Caution, Not Recommended)
- [x] Create terraform/lambda.tf:
  - Lambda function deployment (count = var.enable_lambda_target ? 1 : 0)
  - Lambda IAM role with execution permissions
  - CloudWatch log group with 7-day retention
  - Lambda permission scoped to Gateway role
  - Gateway Lambda target registration via null_resource + AWS CLI
  - Tool schema for assess_client_suitability function
  - archive provider added to main.tf
- [x] Update agent/app.py to include risk profile tool
- [x] Create scripts/test-risk.py to test "Is Apple suitable for a conservative investor?"
- [x] Verify Terraform validates and plans successfully (`terraform validate` passes)
- [x] Deploy with `terraform apply` (enable_lambda_target=true)
- [x] Rebuild agent container and push to ECR
- [x] Test with test-risk.py - verify agent returns suitability assessment
- [x] Perform a critical self-review of all changes and fix any issues found
- [x] COMPLETE - Ready for Phase 5

### Phase 5: Module 4 - MCP Server Gateway Target (Deploy & Test)

**Objective**: Deploy MCP server wrapping Nager.Date API as Gateway target.

**Status**: COMPLETE

- [x] Create docs/04-gateway-mcp.md explaining:
  - MCP (Model Context Protocol) concepts
  - MCP servers on AgentCore Runtime
  - streamable-http transport requirement
  - Why MCP for market calendar (standardised interface, tool discovery)
  - How to enable: set `enable_mcp_target = true`
- [x] Create mcp-server/Dockerfile for MCP server container
- [x] Create mcp-server/requirements.txt (mcp[cli], httpx)
- [x] Create mcp-server/server.py wrapping Nager.Date public holidays API:
  - Uses FastMCP with `stateless_http=True` (required for AgentCore Runtime)
  - Uses `streamable-http` transport (stdio not supported in AgentCore Runtime)
  - Exposes `check_market_holidays` tool (country_code, days_ahead params)
  - Handles multi-year window, error handling for invalid country codes
- [x] Create terraform/mcp.tf:
  - ECR repository for MCP server (count = var.enable_mcp_target ? 1 : 0)
  - IAM role for MCP server Runtime (ECR pull + CloudWatch only)
  - time_sleep resource for IAM propagation
  - null_resource to build and push MCP container image
  - Second AgentCore Runtime for MCP server (mcp_server_runtime_name local)
  - AgentCore Runtime Endpoint for MCP server (mcp_endpoint_name local)
  - aws_iam_role_policy.gateway_mcp_access granting Gateway role InvokeAgentRuntime
  - null_resource registering Gateway MCP_SERVER target with synchronize call
- [x] Update locals.tf with mcp_server_runtime_name and mcp_endpoint_name (underscore convention)
- [x] Add MCP outputs to terraform/outputs.tf
- [x] Update agent/app.py to include check_market_holidays tool
- [x] Create scripts/build-mcp.sh for MCP server Docker build and ECR push
- [x] Create scripts/test-calendar.py with 3 test scenarios
- [x] Verify Terraform validates and plans successfully
- [x] Run Docker build for MCP server and push to ECR
- [x] Deploy with `terraform apply` (enable_mcp_target=true)
- [x] Rebuild agent container and push to ECR
- [x] Test with test-calendar.py - verify agent returns market calendar information
- [x] Perform a critical self-review of all changes and fix any issues found
- [x] COMPLETE - Ready for Phase 6

### Phase 6: Module 5 - AgentCore Memory (Deploy & Test)

**Objective**: Enable persistent memory for advisor and client context.

- [ ] Create docs/05-memory.md explaining:
  - AgentCore Memory concepts (STM vs LTM)
  - Memory strategies (semantic, summary, user preference)
  - Namespace organisation for actors and sessions
  - What to store: advisor preferences, client risk profiles, frequent tickers
  - How to enable: set `enable_memory = true`
- [ ] Create terraform/memory.tf:
  - AgentCore Memory (count = var.enable_memory ? 1 : 0)
  - Memory with user_preference_memory_strategy
  - Memory namespace configuration for advisor/client data
  - Configure event expiry duration (90 days)
- [ ] Update agent/app.py for memory integration:
  - Read from memory at session start
  - Write client details to memory
  - Recall client context without explicit repetition
- [ ] Create scripts/test-memory.py to test memory persistence:
  - Session 1: Provide client details
  - Session 2: Query without repeating details
- [ ] Verify Terraform validates and plans successfully
- [ ] Deploy with `terraform apply` (enable_memory=true)
- [ ] Rebuild agent container and push to ECR
- [ ] Test with test-memory.py - verify client details persist across sessions
- [ ] Perform a critical self-review of all changes and fix any issues found
- [ ] STOP and wait for human review

### Phase 7: Module 6 - AgentCore Identity (Deploy & Test)

**Objective**: Secure MCP target with OAuth 2.0 authentication.

- [ ] Create docs/06-identity.md explaining:
  - AgentCore Identity concepts
  - OAuth 2.0 client credentials flow
  - JWT authorisation for Gateway targets
  - Why FSI requires authenticated service-to-service calls
  - How to enable: set `enable_identity = true`
- [ ] Create terraform/identity.tf:
  - Cognito User Pool (count = var.enable_identity ? 1 : 0)
  - Workload Identity configuration
  - Update MCP Gateway target to require CUSTOM_JWT auth
  - Configure agent with OAuth credentials
- [ ] Update agent/app.py to present credentials for authenticated targets
- [ ] Create scripts/test-auth.py:
  - Test unauthenticated call returns 401
  - Test authenticated call succeeds
- [ ] Verify Terraform validates and plans successfully
- [ ] Deploy with `terraform apply` (enable_identity=true)
- [ ] Rebuild agent container and push to ECR
- [ ] Test with test-auth.py - verify unauthenticated returns 401, authenticated succeeds
- [ ] Perform a critical self-review of all changes and fix any issues found
- [ ] STOP and wait for human review

### Phase 8: Module 7 - AgentCore Observability (Deploy & Test)

**Objective**: Instrument agent and inspect full request traces.

- [ ] Create docs/07-observability.md explaining:
  - AgentCore Observability concepts
  - Distributed tracing and spans
  - How to interpret traces for compliance/audit
  - Latency analysis and optimisation opportunities
  - How to enable: set `enable_observability = true`
- [ ] Create terraform/observability.tf:
  - Enable Observability on Runtime (count = var.enable_observability ? 1 : 0)
  - Configure X-Ray tracing
  - CloudWatch Logs integration
- [ ] Update agent/app.py with observability instrumentation
- [ ] Create scripts/test-trace.py:
  - Send full end-to-end query exercising all tools
  - Document expected trace structure
- [ ] Document how to view trace in AWS console
- [ ] Verify Terraform validates and plans successfully
- [ ] Deploy with `terraform apply` (enable_observability=true)
- [ ] Rebuild agent container and push to ECR
- [ ] Test with test-trace.py - send full query and verify trace in AWS console
- [ ] Perform a critical self-review of all changes and fix any issues found
- [ ] STOP and wait for human review

### Phase 9: Final Integration and Documentation

**Objective**: Complete integration testing and finalise all documentation.

- [ ] Create scripts/test-full.py that runs full end-to-end scenario:
  - Test MarketPulse with complete advisor query
  - Verify all components work together
  - Example: "I'm meeting Sarah Chen at 2pm. She's conservative and interested in Apple. Give me a quick brief."
- [ ] Create scripts/destroy.sh for clean teardown of all resources
- [ ] Update main README.md with:
  - Complete setup instructions
  - Feature flag progression guide
  - Troubleshooting section for common issues
  - Architecture diagram (Mermaid)
- [ ] Verify all module docs are complete and consistent
- [ ] Run `terraform fmt -recursive` to format all Terraform files
- [ ] Run `terraform validate`
- [ ] Verify all Python files have no syntax errors
- [ ] Confirm all success criteria from this plan are met
- [ ] Perform critical self-review of entire workshop
- [ ] STOP and wait for human review

---

## Notes

**Key Technical Decisions:**
1. Single Terraform directory with feature flags - engineers toggle variables rather than navigate directories
2. Local state file for workshop simplicity (no remote backend setup required)
3. Finnhub chosen over Alpha Vantage for simpler API structure
4. MCP server uses streamable-http transport (stdio not supported in AgentCore Runtime)
5. OAuth 2.0 only applied to MCP target (HTTP uses API key, Lambda uses IAM)
6. PUBLIC network mode for workshop simplicity

**Workshop Progression:**
| Module | Feature Flags to Enable | terraform apply |
|--------|------------------------|-----------------|
| 1 | (none - base runtime) | ✓ |
| 2 | enable_gateway, enable_http_target | ✓ |
| 3 | enable_lambda_target | ✓ |
| 4 | enable_mcp_target | ✓ |
| 5 | enable_memory | ✓ |
| 6 | enable_identity | ✓ |
| 7 | enable_observability | ✓ |

---

## Working Notes (for executing agent use)

**Purpose:** Track complex issues, troubleshooting attempts, and problem-solving progress during development.

**Format:** Use this space freely - bullet points, links to documentation, error messages, whatever helps track progress.

### Phase 2 - Runtime Validation Issue (RESOLVED)

**Issue:** Terraform validation failed with error:
```
Error: expected name to match regular expression "^[a-zA-Z][a-zA-Z0-9_]{0,47}$"
```

**Root Cause:** The `awscc_bedrockagentcore_runtime_endpoint` resource name field only accepts alphanumeric characters and underscores, not hyphens. The original code used `${local.agent_name}-endpoint` which contained hyphens from the name_prefix.

**Solution:** 
1. Added new local variable `runtime_endpoint_name` in `terraform/locals.tf` that replaces hyphens with underscores:
   ```hcl
   runtime_endpoint_name = replace("${local.name_prefix}_agent_endpoint", "-", "_")
   ```
2. Updated `terraform/runtime.tf` to use `local.runtime_endpoint_name` instead of the hardcoded string

**Validation:** `terraform validate` now passes successfully.

**Date:** 19/02/2026

---

### Documentation Alignment (23/02/2026) - Phase 3 Doc Review

**Changes made after Phase 3 testing:**

1. **docs/02-gateway-http.md** - Full alignment with actual implementation:
   - Step 1: Removed manual Secrets Manager creation; Terraform manages the secret via `finnhub_api_key` in `terraform.tfvars`
   - Step 2: Changed from "edit app.py" to "review existing code" with correct imports (`from strands import Agent`, `from bedrock_agentcore.runtime import BedrockAgentCoreApp`) and actual tool pattern (plain function, not `@agent.tool` decorator)
   - Step 3: Removed non-existent `enable_runtime` variable; added `finnhub_api_key` to tfvars example
   - Step 4: Clarified no container rebuild needed; environment variables updated in-place by Terraform; fixed expected output to match real output names
   - Step 5: Changed test command from `python scripts/test-agent.py "query"` to `python scripts/test-stock.py`
   - Step 6: Fixed CloudWatch log group path to `/aws/bedrock/agent/marketpulse_workshop_agent`; added AWS console navigation path
   - Tools vs Targets: Replaced non-existent HCL resources (`aws_agentcore_http_target`, `aws_agentcore_tool_association`) with actual OpenAPI spec approach and CLI explanation
   - Verification Checklist: Removed `http_target_id` output reference; updated to real verification steps
   - Common Issues: Replaced `terraform taint aws_agentcore_tool_association.stock_price` / `aws_agentcore_agent.marketpulse` with correct resource names
   - Architecture diagram: Added S3 bucket node (OpenAPI spec storage)
   - Key Takeaways: Replaced "tool associations" with `operationId` linking explanation
   - Cost section: Changed hourly Gateway pricing (wrong model) to per-request reference
   - Vendor reference: Changed "Reuters" to "Refinitiv/LSEG"

2. **terraform/terraform.tfvars.example** - Fixed default region from `us-east-1` to `ap-southeast-2`

3. **README.md** - Quick Start: Changed `.env` instructions to `terraform.tfvars` for Finnhub API key; added `test-stock.py` to project structure

**Remaining docs for future phases:** docs/03-07 still contain `enable_runtime = true` and old import styles - will be fixed when those phases are implemented.

---

### Phase 4 Implementation (23/02/2026) - Lambda Gateway Target

**Status:** COMPLETE - Deployed and tested.

**Files created/modified:**
- `lambda/scorer.py` - Risk profile scorer Lambda handler with volatility/suitability matrix
- `terraform/lambda.tf` - Full Lambda implementation replacing placeholder (archive_file, IAM role, Lambda function, CloudWatch log group, lambda permission, gateway_lambda_access policy, null_resource for target registration)
- `terraform/main.tf` - Added `hashicorp/archive` provider (required for archive_file data source)
- `terraform/outputs.tf` - Added lambda_function_name, lambda_function_arn, lambda_log_group, lambda_target_configured outputs
- `agent/app.py` - Added assess_client_suitability tool, system prompt updated with has_lambda_tool conditional
- `scripts/test-risk.py` - 4 test scenarios covering conservative/moderate/aggressive profiles
- `docs/03-gateway-lambda.md` - Fully rewritten from placeholder to match actual implementation

**Key design decisions:**
- `aws_lambda_permission.allow_gateway` uses `count = (var.enable_gateway && var.enable_lambda_target) ? 1 : 0` to avoid Terraform indexing a non-existent `aws_iam_role.gateway[0]` when enable_gateway=false
- `null_resource.lambda_gateway_target` uses the same pattern for consistency  
- Tool schema is defined inline within the `create-gateway-target` CLI call (same approach as HTTP target uses OpenAPI)
- Lambda function name: `marketpulse-workshop-dev-risk-scorer`
- Lambda handler: `scorer.handler` (file is `scorer.py`)

**Validation:** `terraform validate` passes, all Python files compile cleanly.

---

### Phase 5 Implementation (24/02/2026) - MCP Server Gateway Target

**Status:** COMPLETE - Deployed and tested 25/02/2026.

**Files created/modified:**
- `mcp-server/server.py` - FastMCP server wrapping Nager.Date public holidays API. Uses stateless_http=True (required for AgentCore Runtime) and streamable-http transport. Exposes check_market_holidays tool.
- `mcp-server/requirements.txt` - mcp[cli]>=1.9.0, httpx>=0.27.0
- `mcp-server/Dockerfile` - python:3.11-slim, port 8000, socket-based healthcheck, non-root user bedrock_agentcore
- `terraform/locals.tf` - Added mcp_server_runtime_name and mcp_endpoint_name (underscore-only, per runtime name regex constraint)
- `terraform/mcp.tf` - Full implementation replacing placeholder. ECR, IAM roles, build null_resource, two awscc_bedrockagentcore_runtime resources, gateway_mcp_access policy, null_resource for target registration with synchronize-gateway-targets
- `terraform/outputs.tf` - Added ecr_mcp_repository_url, mcp_server_runtime_name, mcp_server_runtime_id, mcp_server_endpoint_name, mcp_target_configured
- `agent/app.py` - Added check_market_holidays tool stub and has_mcp_tool conditional in system prompt
- `scripts/build-mcp.sh` - Mirror of build-agent.sh for MCP server ECR push
- `scripts/test-calendar.py` - 3 test scenarios for market calendar queries
- `docs/04-gateway-mcp.md` - Fully rewritten from placeholder; includes architecture diagram, step-by-step instructions matching actual implementation

**Key design decisions:**
- Gateway MCP target URL uses URL-encoded Runtime ARN in path; python3 urllib.parse.quote used in null_resource provisioner
- synchronize-gateway-targets called after target creation (tolerates failure with || echo) for tool discovery
- GATEWAY_IAM_ROLE credential type used (no separate OAuth for Module 4; OAuth comes in Module 6)
- stateless_http=True in FastMCP is required; AgentCore provides session isolation
- MCP server IAM role has no Bedrock permissions (only ECR pull + CloudWatch) - correct separation of concerns
- Runtime names use underscore convention to satisfy AWSCC provider regex; hyphenated names used for IAM roles and log groups
