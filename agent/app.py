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
from datetime import datetime
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from strands import Agent
from strands.models import BedrockModel

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialise AgentCore app
app = BedrockAgentCoreApp()

# Configure Bedrock model from environment variable
model_id = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-5-sonnet-20241022-v2:0")
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
# Tool Configuration
# ============================================================================

# Module 2: Stock price tool via Gateway HTTP target
# When Gateway is enabled, we define the tool function and AgentCore automatically
# routes calls through the Gateway to the matching OpenAPI target based on tool name

def get_stock_price(symbol: str) -> dict:
    """
    Retrieves current stock price and trading data for a ticker symbol.
    
    This tool is routed through AgentCore Gateway to the Finnhub API.
    
    Args:
        symbol: Stock ticker symbol (e.g., AAPL, MSFT, TSLA)
        
    Returns:
        dict: Stock quote data with current price, day range, etc.
    """
    # Implementation handled by AgentCore Gateway
    # The Gateway routes this to the OpenAPI target based on function name
    pass

# Module 3: Risk scoring tool via Lambda Gateway target
# When ENABLE_LAMBDA_TARGET is set, AgentCore routes assess_client_suitability
# calls through the Gateway to the risk scorer Lambda function.

def assess_client_suitability(ticker: str, risk_profile: str) -> dict:
    """
    Assesses whether a stock is suitable for a client's risk profile.

    This tool is routed through AgentCore Gateway to the risk scorer Lambda.

    Args:
        ticker:       Stock ticker symbol (e.g., AAPL, TSLA)
        risk_profile: Client risk profile - conservative, moderate, or aggressive

    Returns:
        dict: Suitability label (clear_match, proceed_with_caution, not_suitable)
              and plain-language reasoning for the advisor.
    """
    # Implementation handled by AgentCore Gateway -> Lambda
    pass

# Module 4: Market calendar tool via MCP Gateway target
# When ENABLE_MCP_TARGET is set, AgentCore routes check_market_holidays
# calls through the Gateway to the Market Calendar MCP server.

def check_market_holidays(country_code: str = "AU", days_ahead: int = 7) -> dict:
    """
    Check for public holidays that affect market trading in the next N days.

    This tool is routed through AgentCore Gateway to the Market Calendar MCP server,
    which wraps the Nager.Date public holidays API.

    Args:
        country_code: ISO 3166-1 alpha-2 country code (e.g. AU, US, GB).
                      Defaults to AU for Australian markets.
        days_ahead:   Number of calendar days to look ahead. Defaults to 7.

    Returns:
        dict: Upcoming holidays with dates, names, and trading impact summary.
    """
    # Implementation handled by AgentCore Gateway -> MCP Server
    pass

# Build tool list based on enabled features
tools = []

# Tool configuration - simplified registration pattern
tool_config = [
    ("ENABLE_GATEWAY", get_stock_price, "Gateway enabled - stock price tool available"),
    ("ENABLE_LAMBDA_TARGET", assess_client_suitability, "Lambda target enabled - risk scoring tool available"),
    ("ENABLE_MCP_TARGET", check_market_holidays, "MCP target enabled - market calendar tool available"),
]

for env_var, tool_func, log_msg in tool_config:
    if os.environ.get(env_var, "false").lower() == "true":
        logger.info(log_msg)
        tools.append(tool_func)

# ============================================================================
# Agent Configuration
# ============================================================================

# Determine available tools for system prompt
has_stock_tool = os.environ.get("ENABLE_GATEWAY", "false").lower() == "true"
has_lambda_tool = os.environ.get("ENABLE_LAMBDA_TARGET", "false").lower() == "true"
has_mcp_tool = os.environ.get("ENABLE_MCP_TARGET", "false").lower() == "true"

# Build system prompt based on available tools
base_prompt = """You are MarketPulse, an AI investment brief assistant for financial advisors.

Your role is to help advisors prepare for client meetings by providing:"""

tool_descriptions = []
if has_stock_tool:
    tool_descriptions.append("- Current stock information using the get_stock_price tool")
if has_lambda_tool:
    tool_descriptions.append("- Risk assessments using the assess_client_suitability tool")
if has_mcp_tool:
    tool_descriptions.append("- Market calendar information using the check_market_holidays tool")

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
    guidelines.append("When providing stock prices, always cite the ticker symbol and mention that data is real-time from Finnhub.")
else:
    guidelines.append("In this initial version, you don't have access to live data tools yet. Provide general guidance based on your training data knowledge.")

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
    session_id = payload.get("session_id", "default_session")
    
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