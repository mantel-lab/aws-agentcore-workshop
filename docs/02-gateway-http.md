# Module 2: Add Stock Price API as HTTP Gateway Target

**Duration:** 20 minutes  
**Prerequisites:** Completed [Module 1](01-runtime.md)

## Learning Objectives

By the end of this module, you will:

1. Understand how AgentCore Gateway integrates external APIs
2. Register an HTTP target pointing to Finnhub stock price API
3. Understand how tool routing works between agent code and Gateway targets
4. Query the agent for real-time stock prices
5. Understand the difference between tools and targets

## What is AgentCore Gateway?

AgentCore Gateway is a managed integration layer that:

- **Exposes external services as tools** - APIs, Lambda functions, MCP servers
- **Handles authentication** - API keys, OAuth tokens, AWS SigV4
- **Manages rate limiting** - Prevents overwhelming external services
- **Centralises logging** - All tool calls are logged for audit
- **Provides schema validation** - Ensures requests/responses match expected formats

Gateway sits between your agent and external systems, providing a clean abstraction layer.

## Architecture: Module 2

```mermaid
flowchart TB
    User[Workshop Engineer] -->|Query| Agent[MarketPulse Agent]
    Agent -->|Tool Call| Gateway[AgentCore Gateway]
    Gateway -->|HTTP Request| Finnhub[Finnhub Stock API]
    Finnhub -->|Price Data| Gateway
    Gateway -->|Tool Response| Agent
    Agent -->|Brief| User
    
    Gateway -.->|API Key| Secrets[Secrets Manager]
    Gateway -.->|OpenAPI Spec| S3[S3 Bucket]
    
    classDef runtime fill:#E8EAF6,stroke:#7986CB,color:#3F51B5
    classDef gateway fill:#F3E5F5,stroke:#BA68C8,color:#8E24AA
    classDef external fill:#E0F2F1,stroke:#4DB6AC,color:#00897B
    classDef data fill:#E3F2FD,stroke:#64B5F6,color:#1976D2
    
    class Agent runtime
    class Gateway gateway
    class Finnhub external
    class Secrets,S3 data
```

## Why Finnhub?

**Finnhub** provides a free tier stock data API that's practical for workshops:

- **Free tier** - 60 API calls/minute with free API key
- **No credit card** - Registration only requires email
- **Real-time data** - Current prices, day ranges, trading volume
- **Simple API** - Single endpoint for quote data

**Free tier covers US-listed equities only.** ASX symbols such as `BHP.AX` return
HTTP 403. The workshop therefore uses US tickers (NVDA, MSFT, TSLA, JNJ). This is a
realistic constraint: data entitlements differ by venue, and an agent needs to handle
a tool that legitimately cannot answer. Module 2 covers what the agent does when the
tool fails.

**API endpoint:**
```
GET https://finnhub.io/api/v1/quote?symbol=NVDA&token=YOUR_API_KEY
```

**Response:**
```json
{
  "c": 184.25,  // Current price
  "h": 185.10,  // Day high
  "l": 182.50,  // Day low
  "o": 183.00,  // Open price
  "pc": 183.50, // Previous close
  "t": 1708322400 // Timestamp
}
```

## Step 1: Get a Finnhub API Key

1. Navigate to https://finnhub.io/register
2. Register with your email address
3. Verify your email
4. Copy your API key from the dashboard

You will provide this key via `terraform.tfvars` in Step 3. Terraform stores it in Secrets Manager automatically - no manual secret creation is required.

## Step 2: Review the Agent Code

The Gateway connection is already written in `agent/app.py`. You do not need to modify the agent code for this module.

Review the relevant section:

```python
from mcp.client.streamable_http import streamablehttp_client
from strands import Agent
from strands.tools.mcp import MCPClient

class SigV4HTTPXAuth(httpx.Auth):
    """Signs outgoing MCP requests with SigV4 so the Gateway accepts them."""

    requires_request_body = True  # the signature covers the body

    def auth_flow(self, request):
        frozen = self.credentials.get_frozen_credentials()
        aws_request = AWSRequest(
            method=request.method,
            url=str(request.url),
            data=request.content,
            headers=dict(request.headers),
        )
        SigV4Auth(frozen, "bedrock-agentcore", self.region).add_auth(aws_request)
        request.headers.update(dict(aws_request.headers))
        yield request

client = MCPClient(
    lambda: streamablehttp_client(gateway_url, auth=SigV4HTTPXAuth(aws_region))
)
client.start()               # without this the session is never running
tools = client.list_tools_sync()

agent = Agent(model=model, tools=tools, system_prompt=system_prompt)
```

**What's happening here:**

- AgentCore Gateway is itself an MCP server, reachable at
  `https://<gateway-id>.gateway.bedrock-agentcore.<region>.amazonaws.com/mcp`
- The agent asks the Gateway for its tool catalogue, so every registered target
  (HTTP now, Lambda and MCP in later modules) shows up without agent code changes
- The gateway uses `AWS_IAM` inbound authorisation, so every request must be SigV4 signed
  with the runtime's role credentials. `requires_request_body = True` matters: sign an
  empty body and the Gateway rejects the request
- The agent reads the Gateway ID from SSM at startup rather than from a baked-in
  environment variable, so a rebuilt Gateway does not leave the runtime pointing at a
  stale ID

Tool names arrive prefixed with the target name, for example
`get-stock-price___get_stock_price`. That prefix is how the Gateway routes a call back to
the right target.

> **Common mistake:** declaring a local Python function with an empty `pass` body and
> hoping AgentCore intercepts it. Nothing intercepts it. The tool returns `None`, and the
> model fills the gap with a plausible-sounding price from its training data.


## Step 3: Configure Terraform

Edit `terraform/terraform.tfvars` to enable Gateway and HTTP target, and add your Finnhub API key:

```hcl
# Feature Flags
enable_gateway       = true
enable_http_target   = true
enable_lambda_target = false
enable_mcp_target    = false
enable_memory        = false
enable_identity      = false
enable_observability = false

# Finnhub API Key (required when enable_http_target = true)
finnhub_api_key = "your_finnhub_api_key_here"
```

**What changed:** `enable_gateway` and `enable_http_target` are now `true`. The `finnhub_api_key` tells Terraform to store your key in Secrets Manager.

## Step 4: Deploy

Run Terraform to deploy the Gateway components:

```bash
cd terraform
terraform plan   # Review what will be created
terraform apply
```

**What Terraform creates:**

- IAM role for Gateway with permissions to invoke targets and read Secrets Manager
- S3 bucket for storing the OpenAPI specification
- OpenAPI spec describing the Finnhub quote endpoint (uploaded to S3)
- Secrets Manager secret containing your Finnhub API key
- AgentCore Gateway (via AWS CLI)
- Gateway API key credential provider linked to the secret
- Gateway HTTP target pointing to Finnhub, with the OpenAPI spec as its schema

Terraform also updates the Runtime's `ENABLE_GATEWAY` environment variable to `true`. This activates the `get_stock_price` tool in the running agent.

**You do not need to rebuild the agent container image.** Terraform updates the Runtime environment variables, but a container that is already running keeps the values it started with. The Runtime only picks up the change on its next cold start, so give it a couple of minutes of idle time, or force a restart:

```bash
cd terraform
terraform taint awscc_bedrockagentcore_runtime.agent
terraform apply
```

**Expected output:**

```
Apply complete! Resources: 8 added, 1 changed, 0 destroyed.

Outputs:

agent_endpoint_id = "ep-abc123"
agent_endpoint_name = "marketpulse_workshop_agent_endpoint"
agent_runtime_arn = "arn:aws:bedrock-agentcore:ap-southeast-2:123456789012:runtime/runtime-xyz789"
finnhub_target_configured = true
gateway_id = <sensitive>
openapi_spec_bucket = "marketpulse-workshop-openapi-specs"
```

`gateway_id` is marked sensitive and will not show as plain text. The value is stored in SSM Parameter Store at `/${project_name}/${environment}/gateway-id`.

Wait 1-2 minutes after apply completes for the Runtime to pick up the new environment variables.

## Step 5: Test Stock Price Queries

Use the dedicated stock price test script:

```bash
python scripts/test-stock.py
```

This script runs four queries against the agent: a single stock price, a multi-stock comparison, a trading range query, and an ASX ticker the free tier cannot serve.

**Expected output:**

```
AWS AgentCore Workshop: Testing Stock Price Tool (Module 2)
======================================================================

Retrieving agent configuration from Terraform outputs...
✓ Runtime ARN: arn:aws:bedrock-agentcore:ap-southeast-2:123456789012:runtime/runtime-xyz789
✓ Endpoint Name: marketpulse_workshop_agent_endpoint
✓ Gateway ID: gtw-abc123

Running stock price tests...

Test 1/4: Single stock price query
Query: What is the current price of NVIDIA stock (NVDA)?

Agent Response:
----------------------------------------------------------------------
NVIDIA (NVDA) - Current Market Data

Current Price: $184.25
Day Range: $182.50 - $185.10
Open: $183.00
Previous Close: $183.50
Change: +$0.75 (+0.41%)

Data sourced from Finnhub (real-time).
----------------------------------------------------------------------
```

For multi-stock comparisons - the agent calls `get_stock_price` once per ticker and consolidates the results.

The fourth query asks for `BHP.AX`, which the free tier does not serve. The agent
should report that the price is unavailable rather than produce a number.

### How the test detects invented prices

A confident-sounding answer is not evidence the tool ran. `scripts/test-stock.py`
fetches a quote straight from Finnhub and compares it against the figures in the
agent's answer:

```
Price verification (agent answer vs live Finnhub quote):
  [ok  ] NVDA: verified - agent quoted 184.25 vs live 184.25
  [FAIL] BHP.AX: hallucinated - HTTP 403 from Finnhub, but the agent still quoted figures: [40.49]
```

A `hallucinated` or `no_price` result exits non-zero. Without this check, a broken
Gateway target looks like a passing test, because the model falls back to prices
remembered from training data.

## Step 6: Inspect Agent Logs

The agent logs its activity to CloudWatch. View them with:

```bash
aws logs tail /aws/bedrock/agent/marketpulse_workshop_agent --follow \
    --region ap-southeast-2
```

Replace `marketpulse_workshop_agent` with your actual runtime name if you changed `project_name` or `environment` in `terraform.tfvars`.

**What to look for:**

```
[INFO] MarketPulse received query: What is the current price of NVIDIA stock (NVDA)?
[INFO] Tools available: 1
[INFO] Gateway enabled - stock price tool available
```

You can also view the Gateway configuration in the AWS console:

1. Navigate to **Bedrock** > **AgentCore** > **Gateways**
2. Select your gateway
3. View the registered targets under **Targets**
4. See the `get-stock-price` target with its OpenAPI spec

## Understanding Tools vs Targets

This is a key concept in AgentCore Gateway:

### Tool (Agent's View)

```json
{
  "name": "get-stock-price___get_stock_price",
  "description": "Retrieves current stock price and trading data for a US-listed ticker symbol.",
  "inputSchema": {
    "type": "object",
    "properties": {"symbol": {"type": "string"}},
    "required": ["symbol"]
  }
}
```

This is what `tools/list` returns from the Gateway. The agent knows:
- **What it does** - Get stock price data
- **What it needs** - A ticker symbol string
- **What it returns** - A dict of price data

There is no local implementation. The agent sends a `tools/call` request to the Gateway,
which performs the HTTP call.

### Target (Gateway's Configuration)

The OpenAPI spec (stored in S3 and defined in `terraform/gateway.tf`) describes the external API:

```json
{
  "openapi": "3.0.0",
  "servers": [{ "url": "https://finnhub.io/api/v1" }],
  "paths": {
    "/quote": {
      "get": {
        "operationId": "get_stock_price",
        "parameters": [
          {
            "name": "symbol",
            "in": "query",
            "required": true,
            "schema": { "type": "string" }
          }
        ]
      }
    }
  }
}
```

The `operationId` (`get_stock_price`) is the link between the Python function and the API endpoint.

### The Bridge

The Gateway target is registered via AWS CLI (inside a Terraform `null_resource` in `gateway.tf`). When the agent asks to call `get_stock_price("NVDA")`:

1. AgentCore intercepts the call before the Python body executes
2. Looks up the Gateway target whose `operationId` matches `get_stock_price`
3. Maps the `symbol` argument to the `symbol` query parameter
4. Retrieves the API key from Secrets Manager
5. Sends `GET https://finnhub.io/api/v1/quote?symbol=NVDA&token=xxx`
6. Returns the response to the agent

The agent code never handles URLs, API keys, or HTTP responses directly.

**Why AWS CLI instead of native Terraform resources?**

The AWSCC provider does not yet have full Gateway support. Terraform `null_resource` provisioners call the AWS CLI to create the Gateway and register targets. The Terraform code handles idempotency by checking for an existing Gateway before creating a new one.

## Verification Checklist

- [ ] Finnhub API key added to `terraform.tfvars`
- [ ] `enable_gateway = true` and `enable_http_target = true` in `terraform.tfvars`
- [ ] `terraform apply` completed with `finnhub_target_configured = true` in outputs
- [ ] `python scripts/test-stock.py` returns real stock prices and reports `verified` for each US ticker
- [ ] Agent logs visible in CloudWatch with received queries

## Common Issues

### Agent responds with general knowledge, not real prices

**Cause:** The `ENABLE_GATEWAY` environment variable was not updated on the Runtime, or the Runtime has not picked up the change yet.

**Solution:** Wait 2 minutes after `terraform apply`, then retest. If the issue persists, verify the Runtime environment variables in the AWS console under **Bedrock** > **AgentCore** > **Runtimes** > your runtime > **Configuration**.

### "Gateway not deployed yet" error from test-stock.py

**Cause:** `gateway_id` output is null, meaning the Gateway was not created successfully.

**Solution:** Check for errors in the `null_resource.gateway` provisioner output during `terraform apply`. Common causes are insufficient IAM permissions or AWS CLI not being installed.

### "Authentication failed" on Finnhub

**Cause:** API key was entered incorrectly in `terraform.tfvars`.

**Solution:**
```bash
# Verify the secret value in Secrets Manager
aws secretsmanager get-secret-value \
    --secret-id marketpulse-workshop-finnhub-api-key \
    --region ap-southeast-2 \
    --query 'SecretString' --output text

# If wrong, update terraform.tfvars with the correct key and re-apply
cd terraform && terraform apply
```

### Tool search returns no tools, or `tools/call` fails with "internal error"

**Cause:** The Gateway was created without `searchType: SEMANTIC`, so it has no tool
index for agents to query. Terraform now sets this at creation time.

**Solution:** Gateways created before this setting existed cannot be reliably upgraded
in place - switching an existing gateway to `SEMANTIC` leaves the index in a state where
`tools/call` returns an internal error. Destroy and recreate the Gateway:

```bash
cd terraform
terraform destroy -target=null_resource.finnhub_http_target -target=null_resource.gateway
terraform apply
```

### Test reports "hallucinated" prices

**Cause:** The agent answered with a price it did not retrieve. Either the tool call
failed (check CloudWatch for the Gateway invocation) or the ticker is outside the
Finnhub free tier and the model filled the gap from training data.

**Solution:** Confirm the Gateway target is healthy and use US tickers. The system
prompt already instructs the agent to report unavailable data rather than estimate;
if it still invents figures, the tool result is probably not reaching the model.

### Rate limit errors from Finnhub

**Cause:** Free tier allows 60 calls/minute. Heavy testing can exceed this.

**Solution:** Wait 60 seconds between test batches. For normal workshop usage, the free tier is sufficient.

### Agent returns stale data after enabling Gateway

**Cause:** The Runtime container has not picked up the latest environment variable changes.

**Solution:** Verify `terraform apply` completed cleanly with the Runtime diff showing `ENABLE_GATEWAY` being updated to `true`. If needed, force a Runtime update:
```bash
cd terraform
terraform taint awscc_bedrockagentcore_runtime.agent
terraform apply
```

## FSI Relevance: Gateway in Production

In financial services, AgentCore Gateway provides:

1. **API Management** - Single point to manage all external integrations
2. **Audit Trail** - Every API call logged with request/response
3. **Security** - API keys never exposed to agent code
4. **Rate Limiting** - Prevent costly API overruns
5. **Fallback Handling** - Configure backup data sources if primary fails

This matters for FSI because:
- Market data costs money (Bloomberg, Refinitiv/LSEG)
- Every external call must be auditable for compliance
- API keys are credentials subject to access control policies
- Rate limits prevent runaway spend in automated scenarios

## Discussion Questions

1. **What external services does your team currently integrate with?**
   - Consider: Market data, credit scoring, KYC services

2. **How do you currently manage API keys and credentials?**
   - Think about: Hardcoded, environment variables, secret managers

3. **What benefits do you see from centralising integration logic in Gateway?**
   - Consider: Maintenance, security, observability

4. **When would you use HTTP target vs Lambda target?**
   - Think about: External APIs vs internal logic

## Cost Considerations

**Module 2 additional costs:**

- **AgentCore Gateway** - Charged per request (see current [pricing page](https://aws.amazon.com/bedrock/pricing/))
- **Secrets Manager** - $0.40/month per secret
- **S3** - Negligible for a single small JSON file
- **Finnhub API** - Free tier (60 calls/minute)
- **SSM Parameter Store** - Free for standard parameters

**Estimated additional cost for workshop duration:** Less than $1.

## Next Steps

The agent can now retrieve real-time stock prices via AgentCore Gateway. Finnhub data flows through the Gateway to the agent without any API key handling in agent code.

In [Module 3](03-gateway-lambda.md), you'll add a Lambda target for risk assessment. Unlike HTTP targets (external APIs), Lambda targets run your own code - useful for compliance logic, data transformation, or internal systems.

**Before proceeding:**

- Test multiple stock tickers (NVDA, MSFT, TSLA, JNJ)
- Verify the agent references current prices, not training data values
- Check CloudWatch Logs to confirm the agent is receiving your queries

---

**Key Takeaways:**

- Gateway abstracts integration complexity from agent code
- Tools define what data the agent needs; OpenAPI `operationId` links the function name to the Gateway target
- HTTP targets connect to external REST APIs using an OpenAPI specification
- Secrets Manager stores credentials; agent code never handles API keys
- Terraform manages the full Gateway configuration via feature flags
- The container image does not need rebuilding when only environment variables change