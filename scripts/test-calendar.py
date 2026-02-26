#!/usr/bin/env python3
"""
AWS AgentCore Workshop: MarketPulse - MCP Market Calendar Test Script

Tests the MarketPulse agent's ability to query market holiday information
via the Gateway MCP Server target (Market Calendar MCP server).

This script requires Module 4 to be deployed:
  - enable_gateway = true
  - enable_mcp_target = true
"""

import sys
import time
from pathlib import Path

# Import shared test utilities
from test_utils import get_terraform_output, invoke_agent, get_project_paths


def main() -> int:
    """Main test execution."""

    project_root, terraform_dir = get_project_paths()

    print("AWS AgentCore Workshop: Testing MCP Market Calendar Tool (Module 4)")
    print("=" * 70)
    print()

    if not terraform_dir.exists():
        print(f"Error: Terraform directory not found at {terraform_dir}")
        return 1

    print("Retrieving agent configuration from Terraform outputs...")
    try:
        runtime_arn = get_terraform_output("agent_runtime_arn", terraform_dir)
        endpoint_name = get_terraform_output("agent_endpoint_name", terraform_dir)
        mcp_configured = get_terraform_output("mcp_target_configured", terraform_dir)
        mcp_runtime_name = get_terraform_output("mcp_server_runtime_name", terraform_dir)

        print(f"  Runtime ARN:           {runtime_arn}")
        print(f"  Endpoint Name:         {endpoint_name}")
        print(f"  MCP Configured:        {mcp_configured}")
        print(f"  MCP Server Runtime:    {mcp_runtime_name}")
        print()

        if mcp_configured.lower() != "true":
            print("Error: MCP target not deployed yet!")
            print()
            print("To enable the MCP target:")
            print("  1. Edit terraform/terraform.tfvars:")
            print("       enable_gateway       = true")
            print("       enable_mcp_target    = true")
            print("  2. Run: cd terraform && terraform apply")
            print("  3. Rebuild agent: ./scripts/build-agent.sh")
            print("  4. Wait 3-5 minutes for runtimes to start")
            return 1

    except RuntimeError as e:
        print(f"Error: {e}")
        print()
        print("Make sure you have:")
        print("  1. Set enable_mcp_target = true in terraform.tfvars")
        print("  2. Run 'terraform apply'")
        print("  3. Built and pushed the MCP server: './scripts/build-mcp.sh'")
        print("  4. Rebuilt the agent: './scripts/build-agent.sh'")
        return 1

    # ---------------------------------------------------------------------------
    # Test scenarios covering market calendar queries
    # ---------------------------------------------------------------------------
    test_cases = [
        {
            "prompt": "Are there any market holidays in Australia this week?",
            "description": "Basic Australian market holiday check",
        },
        {
            "prompt": (
                "I'm planning to execute a large AAPL trade for a client on Monday. "
                "Are there any market closures in the next 7 days that could affect timing?"
            ),
            "description": "Trade timing + holiday awareness",
        },
        {
            "prompt": (
                "Check US market holidays for the next 14 days. "
                "My client wants to buy MSFT and needs to know the best week to act."
            ),
            "description": "US market holidays over 2-week window",
        },
    ]

    print(f"Running {len(test_cases)} market calendar tests...")
    print()

    for i, test in enumerate(test_cases, 1):
        print(f"Test {i}/{len(test_cases)}: {test['description']}")
        print(f"Query: {test['prompt']}")
        print()

        try:
            result = invoke_agent(
                runtime_arn=runtime_arn,
                endpoint_name=endpoint_name,
                prompt=test["prompt"],
                session_prefix="calendar-test",
            )

            print("Agent Response:")
            print("-" * 70)
            print(result["response"])
            print("-" * 70)
            print()

            if i < len(test_cases):
                print("Waiting 2 seconds before next query...")
                print()
                time.sleep(2)

        except Exception as e:
            print(f"Error invoking agent: {e}")
            import traceback
            traceback.print_exc()
            return 1

    print()
    print("=" * 70)
    print("All market calendar tests completed!")
    print()
    print("Next steps:")
    print("  - Review MCP server logs:")
    print(f"      aws logs tail /aws/bedrock-agentcore/runtime/{mcp_runtime_name} --follow")
    print("  - Try different country codes: US, GB, NZ, JP")
    print("  - Proceed to Module 5 to add persistent memory")
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
