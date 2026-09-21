"""
MarketPulse Agent - Investment Brief Assistant for Financial Advisors

This agent helps advisors prepare for client meetings by providing stock information,
risk assessments, and market calendar data. Features are enabled progressively through
the workshop modules.

Module 1: Basic conversational agent (no tools)
Module 2: Stock price data via HTTP Gateway target
Module 3: Risk assessment via Lambda Gateway target
Module 4: Market calendar via MCP Gateway target
Module 5: Memory for persistent context
Module 6: OAuth 2.0 authentication for MCP
Module 7: Observability with distributed tracing

Observability (Module 7):
When AGENT_OBSERVABILITY_ENABLED=true, the agent is automatically instrumented via
OpenTelemetry. All requests, tool calls, memory operations, and LLM invocations are
traced to AWS X-Ray. No code changes required - instrumentation is handled by:
- strands-agents[otel] package
- aws-opentelemetry-distro in Dockerfile
- opentelemetry-instrument wrapper in container CMD
"""

import os
import logging
import uuid
from datetime import datetime

import boto3
import httpx
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from mcp.client.streamable_http import streamablehttp_client
from strands import Agent
from strands.models import BedrockModel
from strands.tools.mcp import MCPClient

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialise AgentCore app
app = BedrockAgentCoreApp()

# Configure Bedrock model from environment variable
model_id = os.environ.get("BEDROCK_MODEL_ID", "au.anthropic.claude-sonnet-4-5-20250929-v1:0")
model = BedrockModel(
    model_id=model_id
)

# Check if memory is enabled
enable_memory = os.environ.get("ENABLE_MEMORY", "false").lower() == "true"
memory_id = os.environ.get("MEMORY_ID", "")
aws_region = os.environ.get("AWS_REGION", "ap-southeast-2")

# Import memory components if enabled
if enable_memory and memory_id:
    from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig
    from bedrock_agentcore.memory.integrations.strands.session_manager import AgentCoreMemorySessionManager
    logger.info(f"Memory enabled - using Memory ID: {memory_id}")
else:
    logger.info("Memory disabled")

# ============================================================================
# Gateway Tools
# ============================================================================
#
# AgentCore Gateway is an MCP server. The agent connects to its /mcp endpoint
# and asks for the tool catalogue, which covers every registered target:
#   Module 2: get_stock_price  (HTTP target   -> Finnhub)
#   Module 3: assess_client_suitability (Lambda target -> risk scorer)
#   Module 4: check_market_holidays (MCP target -> market calendar server)
#
# Declaring local Python functions with empty bodies does not work: nothing
# intercepts the call, the tool returns None, and the model answers from
# training data instead of live data.


class SigV4HTTPXAuth(httpx.Auth):
    """Signs outgoing MCP requests with SigV4 so the Gateway accepts them."""

    # The signature covers the request body, so httpx must read it before signing
    requires_request_body = True

    def __init__(self, region: str, service: str = "bedrock-agentcore"):
        self.region = region
        self.service = service
        self.credentials = boto3.Session().get_credentials()

    def auth_flow(self, request: httpx.Request):
        # Resolve on each request: container credentials rotate
        frozen = self.credentials.get_frozen_credentials()
        aws_request = AWSRequest(
            method=request.method,
            url=str(request.url),
            data=request.content,
            headers=dict(request.headers),
        )
        SigV4Auth(frozen, self.service, self.region).add_auth(aws_request)
        request.headers.update(dict(aws_request.headers))
        yield request


def resolve_gateway_url() -> str:
    """
    Build the Gateway MCP endpoint URL.

    GATEWAY_URL wins if set. Otherwise the Gateway ID is read from SSM at
    startup, which avoids baking a stale ID into the runtime configuration.
    The ID already contains the project prefix, so it is used verbatim.
    """
    explicit_url = os.environ.get("GATEWAY_URL", "").strip()
    if explicit_url:
        return explicit_url

    parameter_name = os.environ.get("GATEWAY_ID_PARAMETER", "").strip()
    if not parameter_name:
        return ""

    ssm = boto3.client("ssm", region_name=aws_region)
    gateway_id = ssm.get_parameter(Name=parameter_name)["Parameter"]["Value"]
    return f"https://{gateway_id}.gateway.bedrock-agentcore.{aws_region}.amazonaws.com/mcp"


def connect_to_gateway() -> tuple[MCPClient | None, list]:
    """
    Open an MCP session to the Gateway and fetch its tools.

    Returns an empty tool list on failure rather than raising: the container
    must still start and serve requests so the failure is visible in the logs
    and in the agent's answers.
    """
    try:
        gateway_url = resolve_gateway_url()
        if not gateway_url:
            logger.error("Gateway enabled but neither GATEWAY_URL nor GATEWAY_ID_PARAMETER is set")
            return None, []

        logger.info(f"Connecting to Gateway: {gateway_url}")
        client = MCPClient(
            lambda: streamablehttp_client(gateway_url, auth=SigV4HTTPXAuth(aws_region))
        )
        # Without start() the session is never running and every tool call fails
        client.start()

        tools = client.list_tools_sync()
        logger.info(f"Gateway tools loaded: {[getattr(t, 'tool_name', t) for t in tools]}")
        return client, tools
    except Exception:
        logger.exception("Failed to connect to the Gateway - the agent will run without tools")
        return None, []


enable_gateway = os.environ.get("ENABLE_GATEWAY", "false").lower() == "true"

gateway_client = None
tools = []

if enable_gateway:
    gateway_client, tools = connect_to_gateway()
else:
    logger.info("Gateway disabled - agent runs without tools")

# ============================================================================
# Agent Configuration
# ============================================================================

# Determine available tools for system prompt
# Gateway tool names are prefixed with the target name (for example
# get-stock-price___get_stock_price), so the prompt describes capabilities
# rather than naming tools the model would have to match exactly.
has_stock_tool = enable_gateway and bool(tools)
has_lambda_tool = has_stock_tool and os.environ.get("ENABLE_LAMBDA_TARGET", "false").lower() == "true"
has_mcp_tool = has_stock_tool and os.environ.get("ENABLE_MCP_TARGET", "false").lower() == "true"

# Build system prompt based on available tools
base_prompt = """You are MarketPulse, an AI investment brief assistant for financial advisors.

Your role is to help advisors prepare for client meetings by providing:"""

tool_descriptions = []
if has_stock_tool:
    tool_descriptions.append("- Current stock information using the stock price tool")
if has_lambda_tool:
    tool_descriptions.append("- Risk assessments using the client suitability tool")
if has_mcp_tool:
    tool_descriptions.append("- Market calendar information using the market holidays tool")

if not tool_descriptions:
    tool_descriptions.append("- Stock information (when tools are available)")
    tool_descriptions.append("- Risk assessments (when tools are available)")
    tool_descriptions.append("- Market calendar information (when tools are available)")

guidelines = ["Always be professional, concise, and focused on actionable insights."]
guidelines.append("Risk profiles are: conservative, moderate, or aggressive.")

if has_lambda_tool:
    guidelines.append("When helping with suitability queries, always retrieve the current stock price first, then assess suitability. Present both together as a concise brief.")

if has_mcp_tool:
    guidelines.append("When discussing trade timing, check for upcoming market holidays. Alert the advisor to any closures that could affect execution.")

if has_stock_tool:
    guidelines.append(
        "Every price you state must come from a stock price tool call made during this turn. "
        "Never estimate a price, never recall one from training data, and never reuse a price "
        "from earlier in the conversation without calling the tool again."
    )
    guidelines.append(
        "Quote prices in USD and cite the ticker symbol. The Finnhub free tier covers US-listed "
        "equities only, so ASX tickers such as BHP.AX return an access error or zeroed quote. "
        "When that happens, say the price is unavailable and why, and suggest a US-listed "
        "alternative if one exists. Do not fill the gap with a made-up number."
    )
elif enable_gateway:
    guidelines.append(
        "Your tools failed to load, so you have no live market data in this session. Say so "
        "plainly when asked for prices, suitability assessments or market holidays, and do not "
        "answer those questions from memory."
    )
else:
    guidelines.append("In this initial version, you don't have access to live data tools yet. Provide general guidance based on your training data knowledge, and state clearly that any figure you mention is illustrative rather than live market data.")

system_prompt = f"{base_prompt}\n" + "\n".join(tool_descriptions) + "\n\n" + "\n".join(guidelines)

# When memory is disabled, create agent at module level (stateless agent)
# When memory is enabled, agent will be created per-request with session_manager
agent_instance = None

if not enable_memory:
    # Create stateless agent (no memory)
    agent_instance = Agent(
        model=model,
        tools=tools,
        system_prompt=system_prompt
    )
    logger.info("Agent created without memory (stateless mode)")

@app.entrypoint
def marketpulse_agent(payload):
    """
    Agent invocation entrypoint.
    
    AgentCore Runtime will call this function with the request payload.
    The payload contains a 'prompt' field with the user's query.
    
    Supports memory integration when ENABLE_MEMORY=true:
    - actor_id: Identifies the advisor (defaults to "advisor_001")
    - session_id: Identifies the conversation session (defaults to "default_session")
    
    Returns the agent's response as a string.
    """
    user_input = payload.get("prompt")
    logger.info(f"MarketPulse received query: {user_input}")
    logger.info(f"Tools available: {len(tools)}")
    
    # Use module-level agent if memory is disabled
    if not enable_memory:
        response = agent_instance(user_input)
        return response.message['content'][0]['text']
    
    # Memory-enabled path: Create agent with session manager per request
    # Extract memory context from payload (or use defaults for workshop)
    actor_id = payload.get("actor_id", "advisor_001")
    # Session IDs must be minimum 33 characters for AgentCore Memory API validation
    session_id = payload.get("session_id", f"default-session-{str(uuid.uuid4())}")
    
    logger.info(f"Memory enabled - actor_id: {actor_id}, session_id: {session_id}")
    
    # Configure memory for this request
    memory_config = AgentCoreMemoryConfig(
        memory_id=memory_id,
        session_id=session_id,
        actor_id=actor_id
    )
    
    # Create session manager
    session_manager = AgentCoreMemorySessionManager(
        agentcore_memory_config=memory_config,
        region_name=aws_region
    )
    
    # Create agent with memory
    agent_with_memory = Agent(
        model=model,
        tools=tools,
        system_prompt=system_prompt,
        session_manager=session_manager
    )
    
    # Invoke agent (session manager handles memory read/write)
    response = agent_with_memory(user_input)
    
    # Extract text response from Strands agent
    return response.message['content'][0]['text']

if __name__ == "__main__":
    # Let AgentCore handle server startup
    # It will automatically listen on port 8080 and implement required endpoints
    app.run()