#!/usr/bin/env python3
"""
AWS AgentCore Workshop: MarketPulse - Observability Trace Test Script

Tests AgentCore Observability by sending a complex query that exercises multiple tools,
generating a complete distributed trace that can be viewed in AWS X-Ray console.

This demonstrates:
- Request tracing across all components
- Tool call visibility (HTTP, Lambda, MCP targets)
- Memory operations (if enabled)
- LLM invocations
- Performance metrics for each span
"""

import sys
import uuid
import json
from pathlib import Path

# Import shared test utilities
from test_utils import get_terraform_output, invoke_agent, get_project_paths


def print_trace_guide(region: str, memory_enabled: str = "false"):
    """Print instructions for viewing the trace in AWS console."""
    print()
    print("=" * 60)
    print("VIEWING THE TRACE IN AWS X-RAY")
    print("=" * 60)
    print()
    print("To view the distributed trace for this request:")
    print()
    print("1. Open AWS X-Ray Console:")
    print(f"   https://console.aws.amazon.com/xray/home?region={region}#/traces")
    print()
    print("2. In the left sidebar, click 'Traces'")
    print()
    print("3. The trace should appear in the list within 10-30 seconds")
    print("   (Traces can take a moment to be indexed)")
    print()
    print("4. Click on the trace to view the timeline")
    print()
    print("What you'll see in the trace:")
    print("- Agent request span (root)")
    print("- LLM invocation spans (Bedrock Claude calls)")
    print("- Tool call spans:")
    print("  - get_stock_price → Gateway HTTP → Finnhub API")
    print("  - assess_client_suitability → Gateway Lambda → Risk Scorer")
    print("  - check_market_holidays → Gateway MCP → Market Calendar")
    if memory_enabled.lower() == "true":
        print("  - Memory read/write operations")
    print()
    print("Each span shows:")
    print("- Duration (how long it took)")
    print("- Status (success/error)")
    print("- Metadata (request/response details)")
    print()
    print("=" * 60)


def main() -> int:
    """Main test execution."""

    project_root, terraform_dir = get_project_paths()
    
    print("AWS AgentCore Workshop: Testing Observability & Tracing")
    print("=" * 60)
    print()
    
    # Check Terraform directory exists
    if not terraform_dir.exists():
        print(f"Error: Terraform directory not found at {terraform_dir}")
        return 1
    
    # Retrieve agent configuration from Terraform outputs
    print("Retrieving agent configuration from Terraform outputs...")
    try:
        runtime_arn = get_terraform_output("agent_runtime_arn", terraform_dir)
        endpoint_name = get_terraform_output("agent_endpoint_name", terraform_dir)
        observability_enabled = get_terraform_output("observability_enabled", terraform_dir)
        region = get_terraform_output("aws_region", terraform_dir)
        print(f"✓ Runtime ARN: {runtime_arn}")
        print(f"✓ Endpoint Name: {endpoint_name}")
        print(f"✓ Region: {region}")
        print()
    except RuntimeError as e:
        print(f"Error: {e}")
        print()
        print("Make sure you have deployed the infrastructure with 'terraform apply'")
        return 1
    
    # Check if observability is enabled
    if observability_enabled.lower() != "true":
        print("❌ Observability is not enabled!")
        print()
        print("To enable observability:")
        print("1. Edit terraform.tfvars and set: enable_observability = true")
        print("2. Run: terraform apply")
        print("3. Rebuild the agent container: ./scripts/build-agent.sh")
        print("4. Re-run this test")
        print()
        print("Note: Even without enable_observability=true, AgentCore provides")
        print("basic CloudWatch logs. Enabling observability adds X-Ray distributed")
        print("tracing for full request visibility.")
        return 1
    print("✓ Observability is enabled")
    print()
    
    # Check which features are enabled
    gateway_enabled = get_terraform_output("gateway_configured", terraform_dir)
    lambda_enabled = get_terraform_output("lambda_target_configured", terraform_dir)
    mcp_enabled = get_terraform_output("mcp_target_configured", terraform_dir)
    memory_enabled = get_terraform_output("memory_enabled", terraform_dir)
    
    print("Feature Status:")
    print(f"  Gateway (HTTP): {gateway_enabled}")
    print(f"  Lambda Target:  {lambda_enabled}")
    print(f"  MCP Target:     {mcp_enabled}")
    print(f"  Memory:         {memory_enabled}")
    print()
    
    if gateway_enabled.lower() != "true" or lambda_enabled.lower() != "true" or mcp_enabled.lower() != "true":
        print("⚠️  Warning: Some tools are not enabled.")
        print("   For a complete trace example, enable all features.")
        print("   The trace will only show enabled components.")
        print()
    
    # Generate unique session ID for this test
    # Note: runtimeSessionId must be at least 33 characters
    test_run_id = str(uuid.uuid4())
    session_id = f"trace-test-session-{test_run_id}"
    
    print(f"Session ID: {session_id}")
    print()
    
    # ========================================================================
    # Send complex query that exercises all tools
    # ========================================================================
    
    print("Sending complex query to generate complete trace...")
    print("-" * 60)
    
    # This query is designed to trigger all available tools for comprehensive tracing
    query = """I'm meeting with a new client tomorrow. They're interested in BHP Group (BHP.AX).
    
Can you help me prepare a brief that includes:
1. Current stock price for BHP.AX
2. Suitability assessment for a conservative investor
3. Any Australian market holidays coming up in the next 7 days

Please provide a concise summary I can review before the meeting."""
    
    print(f"Query: {query}")
    print()
    print("Invoking agent...")
    print()
    
    try:
        response = invoke_agent(
            runtime_arn=runtime_arn,
            endpoint_name=endpoint_name,
            prompt=query,
            session_id_override=session_id
        )
        
        print("✓ Agent Response:")
        print("-" * 60)
        print(response["response"])
        print("-" * 60)
        print()
        
        # Extract trace information if available in the AWS SDK response metadata
        print("Note: The agent response above was traced to AWS X-Ray.")
        print("Trace data includes:")
        print("- Request ID (correlation)")
        print("- Each tool invocation")
        print("- Gateway routing")
        print("- External API calls")
        print("- Duration and status for each operation")
        
    except Exception as e:
        print(f"❌ Error invoking agent: {e}")
        return 1
    
    # ========================================================================
    # Print guide for viewing trace in AWS console
    # ========================================================================
    
    print_trace_guide(region, memory_enabled)
    
    # Additional observability features
    print()
    print("ADDITIONAL OBSERVABILITY FEATURES")
    print("=" * 60)
    print()
    print("1. CloudWatch Logs Insights")
    print("   Query structured logs with trace correlation:")
    print(f"   https://console.aws.amazon.com/cloudwatch/home?region={region}#logsV2:logs-insights")
    print()
    print("   Example query:")
    print("   fields @timestamp, @message, trace_id, span_id")
    print("   | filter @message like /tool/")
    print("   | sort @timestamp desc")
    print()
    print("2. GenAI Observability Dashboard")
    print("   View agent-specific metrics:")
    print(f"   https://console.aws.amazon.com/cloudwatch/home?region={region}#gen-ai-observability")
    print()
    print("3. X-Ray Service Map")
    print("   Visualise component dependencies:")
    print(f"   https://console.aws.amazon.com/xray/home?region={region}#/service-map")
    print()
    print("=" * 60)
    print()
    print("✅ Trace test complete!")
    print()
    print("Next steps:")
    print("1. Open X-Ray console and examine the trace timeline")
    print("2. Identify which tool call took longest")
    print("3. Check for any errors in the trace")
    print("4. Review CloudWatch logs with trace_id correlation")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
