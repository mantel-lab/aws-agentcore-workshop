#!/usr/bin/env python3
"""
AWS AgentCore Workshop: MarketPulse - Full End-to-End Test Script

Tests the complete MarketPulse assistant by running a realistic advisor scenario
that exercises all AgentCore capabilities:
- Runtime (agent execution)
- Gateway HTTP target (stock price via Finnhub)
- Gateway Lambda target (risk assessment)
- Gateway MCP target (market calendar)
- Memory (client context persistence)
- Identity (OAuth 2.0 authentication to MCP target)
- Observability (distributed tracing)

This is the culmination test demonstrating a production-ready FSI agent.
"""

import sys
import uuid
from pathlib import Path

# Import shared test utilities
from test_utils import get_terraform_output, invoke_agent, get_project_paths


def print_trace_guide(region: str):
    """Print instructions for viewing the trace in AWS console."""
    print()
    print("=" * 60)
    print("VIEWING THE DISTRIBUTED TRACE")
    print("=" * 60)
    print()
    print("To view the complete end-to-end trace for this request:")
    print()
    print("1. Open AWS X-Ray Console:")
    print(f"   https://console.aws.amazon.com/xray/home?region={region}#/traces")
    print()
    print("2. In the left sidebar, click 'Traces'")
    print()
    print("3. The trace should appear in the list within 10-30 seconds")
    print()
    print("4. Click on the trace to view the complete timeline")
    print()
    print("The trace shows:")
    print("- Agent request span (root)")
    print("- LLM invocations (Bedrock Claude calls)")
    print("- Memory read/write operations")
    print("- Stock price tool → Gateway HTTP → Finnhub API")
    print("- Risk assessment tool → Gateway Lambda → Scorer function")
    print("- Market calendar tool → Gateway MCP → Nager.Date API")
    print("- OAuth 2.0 token acquisition for MCP authentication")
    print()
    print("Each span includes duration, status, and metadata.")
    print("=" * 60)


def main() -> int:
    """Main test execution."""

    project_root, terraform_dir = get_project_paths()
    
    print("AWS AgentCore Workshop: MarketPulse Full End-to-End Test")
    print("=" * 60)
    print()
    print("This test runs a realistic advisor scenario that exercises ALL")
    print("AgentCore capabilities in a single conversation flow.")
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
    
    # Check which features are enabled
    print("Checking enabled features...")
    try:
        gateway_enabled = get_terraform_output("gateway_configured", terraform_dir)
        http_enabled = get_terraform_output("finnhub_target_configured", terraform_dir)
        lambda_enabled = get_terraform_output("lambda_target_configured", terraform_dir)
        mcp_enabled = get_terraform_output("mcp_target_configured", terraform_dir)
        memory_enabled = get_terraform_output("memory_enabled", terraform_dir)
        identity_enabled = get_terraform_output("mcp_authentication_enabled", terraform_dir)
        observability_enabled = get_terraform_output("observability_enabled", terraform_dir)
    except RuntimeError as e:
        print(f"Error retrieving feature configuration: {e}")
        return 1
    
    print(f"  Runtime:        ✓ (always enabled)")
    print(f"  Gateway:        {'✓' if gateway_enabled.lower() == 'true' else '✗'}")
    print(f"  HTTP Target:    {'✓' if http_enabled.lower() == 'true' else '✗'}")
    print(f"  Lambda Target:  {'✓' if lambda_enabled.lower() == 'true' else '✗'}")
    print(f"  MCP Target:     {'✓' if mcp_enabled.lower() == 'true' else '✗'}")
    print(f"  Memory:         {'✓' if memory_enabled.lower() == 'true' else '✗'}")
    print(f"  Identity:       {'✓' if identity_enabled.lower() == 'true' else '✗'}")
    print(f"  Observability:  {'✓' if observability_enabled.lower() == 'true' else '✗'}")
    print()
    
    # Check if all features are enabled
    all_enabled = all([
        gateway_enabled.lower() == "true",
        http_enabled.lower() == "true",
        lambda_enabled.lower() == "true",
        mcp_enabled.lower() == "true",
        memory_enabled.lower() == "true",
        identity_enabled.lower() == "true",
        observability_enabled.lower() == "true",
    ])
    
    if not all_enabled:
        print("⚠️  WARNING: Not all features are enabled!")
        print()
        print("This test is designed to exercise the complete MarketPulse system.")
        print("For full functionality, enable all features by updating terraform.tfvars:")
        print()
        print("  enable_gateway        = true")
        print("  enable_http_target    = true")
        print("  enable_lambda_target  = true")
        print("  enable_mcp_target     = true")
        print("  enable_memory         = true")
        print("  enable_identity       = true")
        print("  enable_observability  = true")
        print()
        print("Then run: terraform apply && ./scripts/build-agent.sh")
        print()
        
        response = input("Continue with partial functionality? (y/N): ")
        if response.lower() != 'y':
            print("Test cancelled. Enable all features and try again.")
            return 0
        print()
    
    # Generate unique session ID for this test
    # Note: runtimeSessionId must be at least 33 characters
    test_run_id = str(uuid.uuid4())
    actor_id = f"advisor-{test_run_id}"
    session_id = f"full-test-session-{test_run_id}"
    
    print(f"Test Run ID: {test_run_id}")
    print(f"Actor ID: {actor_id[:50]}...")
    print(f"Session ID: {session_id[:50]}...")
    print()
    
    # ========================================================================
    # Scenario: Advisor preparing for a client meeting
    # ========================================================================
    
    print("=" * 60)
    print("SCENARIO: Preparing for Client Meeting")
    print("=" * 60)
    print()
    print("You are a financial advisor preparing for a meeting with")
    print("Sarah Chen at 2pm. She's 45 years old, conservative risk")
    print("profile, and interested in established tech companies.")
    print()
    print("You need to prepare a brief on BHP.AX that includes:")
    print("- Current stock price")
    print("- Suitability assessment for her risk profile")
    print("- Any upcoming Australian market holidays that might affect trading")
    print()
    print("-" * 60)
    
    query = """I'm meeting Sarah Chen at 2pm. She's 45 years old with a conservative 
risk profile and is interested in established tech companies for her retirement portfolio. 

Can you help me prepare a brief on BHP.AX that includes:
1. Current stock price
2. Suitability assessment for her conservative profile
3. Any Australian market holidays coming up in the next 7 days that might affect trading

Keep it concise - I need this for a quick pre-meeting review."""
    
    print(f"Sending query...")
    print()
    
    # Invoke agent
    try:
        result = invoke_agent(
            runtime_arn=runtime_arn,
            endpoint_name=endpoint_name,
            prompt=query,
            session_prefix="full-test",
            actor_id=actor_id,
            session_id_override=session_id,
        )
        
        print("=" * 60)
        print("MARKETPULSE RESPONSE:")
        print("=" * 60)
        print()
        print(result["response"])
        print()
        print("=" * 60)
        print()
        print("✓ Full end-to-end test completed successfully!")
        print()
        print(f"Session ID: {result['session_id']}")
        print(f"Request ID: {result['response_id']}")
        print()
        
        # Print trace viewing instructions if observability is enabled
        if observability_enabled.lower() == "true":
            print_trace_guide(region)
        else:
            print("Note: Observability is not enabled. To view distributed traces,")
            print("enable observability in terraform.tfvars and redeploy.")
        
        print()
        print("=" * 60)
        print("WORKSHOP COMPLETE!")
        print("=" * 60)
        print()
        print("You have successfully deployed and tested a production-ready")
        print("FSI agent using AWS Bedrock AgentCore. This agent demonstrates:")
        print()
        print("✓ Containerised agent runtime")
        print("✓ External API integration via Gateway HTTP targets")
        print("✓ Business logic via Gateway Lambda targets")
        print("✓ Standardised tool interface via Gateway MCP targets")
        print("✓ Persistent memory for client context")
        print("✓ OAuth 2.0 authentication for service-to-service calls")
        print("✓ Distributed tracing for observability")
        print()
        print("This reference implementation can be adapted for:")
        print("- Wealth management advisor assistants")
        print("- Risk assessment and compliance tools")
        print("- Portfolio analysis agents")
        print("- Client onboarding automation")
        print()
        print("Next steps:")
        print("- Review the distributed trace in AWS X-Ray")
        print("- Examine CloudWatch logs for each component")
        print("- Explore the terraform/ directory for IaC patterns")
        print("- Adapt the code for your own use cases")
        print()
        print("To tear down all resources: terraform destroy")
        print()
        
        return 0
        
    except Exception as e:
        print(f"Error invoking agent: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
