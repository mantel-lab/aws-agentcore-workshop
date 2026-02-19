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
"""

import os
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from strands import Agent
from strands.models import BedrockModel

# Initialise AgentCore app
app = BedrockAgentCoreApp()

# Configure Bedrock model from environment variable
model_id = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-5-sonnet-20241022-v2:0")
model = BedrockModel(
    model_id=model_id
)

# Create the MarketPulse agent
agent = Agent(
    model=model,
    tools=[],  # Tools will be added in later modules
    system_prompt="""
You are MarketPulse, an AI investment brief assistant for financial advisors.

Your role is to help advisors prepare for client meetings by providing:
- Current stock information (when tools are available)
- Risk assessments based on client profiles (when tools are available)
- Market calendar information (when tools are available)

Always be professional, concise, and focused on actionable insights.

In this initial version, you don't have access to live data tools yet.
Provide general guidance based on your training data knowledge, and acknowledge
that you'll have more capabilities as additional modules are enabled.
"""
)

@app.entrypoint
def marketpulse_agent(payload):
    """
    Agent invocation entrypoint.
    
    AgentCore Runtime will call this function with the request payload.
    The payload contains a 'prompt' field with the user's query.
    
    Returns the agent's response as a string.
    """
    user_input = payload.get("prompt")
    print(f"MarketPulse received query: {user_input}")
    
    response = agent(user_input)
    
    # Extract text response from Strands agent
    return response.message['content'][0]['text']

if __name__ == "__main__":
    # Let AgentCore handle server startup
    # It will automatically listen on port 8080 and implement required endpoints
    app.run()