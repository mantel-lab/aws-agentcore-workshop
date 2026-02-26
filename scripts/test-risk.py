#!/usr/bin/env python3
"""
AWS AgentCore Workshop: MarketPulse - Lambda Risk Scoring Test Script

Tests the MarketPulse agent's ability to assess client suitability via the
Gateway Lambda target (risk scorer).

This script requires Module 3 to be deployed:
  - enable_gateway = true
  - enable_lambda_target = true
"""

import sys
import time
from pathlib import Path

# Import shared test utilities
from test_utils import get_terraform_output, invoke_agent, get_project_paths


def main() -> int:
    """Main test execution."""

    project_root, terraform_dir = get_project_paths()

    print("AWS AgentCore Workshop: Testing Lambda Risk Scoring Tool (Module 3)")
    print("=" * 70)
    print()

    if not terraform_dir.exists():
        print(f"Error: Terraform directory not found at {terraform_dir}")
        return 1

    print("Retrieving agent configuration from Terraform outputs...")
    try:
        runtime_arn = get_terraform_output("agent_runtime_arn", terraform_dir)
        endpoint_name = get_terraform_output("agent_endpoint_name", terraform_dir)
        lambda_configured = get_terraform_output("lambda_target_configured", terraform_dir)
        lambda_name = get_terraform_output("lambda_function_name", terraform_dir)

        print(f"  Runtime ARN:       {runtime_arn}")
        print(f"  Endpoint Name:     {endpoint_name}")
        print(f"  Lambda Configured: {lambda_configured}")
        print(f"  Lambda Function:   {lambda_name}")
        print()

        if lambda_configured.lower() != "true":
            print("Error: Lambda target not deployed yet!")
            print()
            print("To enable the Lambda target:")
            print("  1. Edit terraform/terraform.tfvars:")
            print("       enable_gateway = true")
            print("       enable_http_target = true")
            print("       enable_lambda_target = true")
            print("  2. Run: cd terraform && terraform apply")
            print("  3. Rebuild agent: ./scripts/build-agent.sh")
            print("  4. Wait 2-3 minutes for runtime to restart")
            return 1

    except RuntimeError as e:
        print(f"Error: {e}")
        print()
        print("Make sure you have:")
        print("  1. Set enable_lambda_target = true in terraform.tfvars")
        print("  2. Run 'terraform apply'")
        print("  3. Rebuilt the agent with './scripts/build-agent.sh'")
        return 1

    # ---------------------------------------------------------------------------
    # Test scenarios: conservative, moderate, and aggressive risk profiles
    # ---------------------------------------------------------------------------
    test_cases = [
        {
            "prompt": (
                "I'm meeting with Sarah Chen, a conservative investor. "
                "Is Apple (AAPL) suitable for her portfolio?"
            ),
            "description": "Conservative investor + low volatility stock (expect: clear match)",
        },
        {
            "prompt": (
                "My client James Wong has an aggressive risk profile. "
                "He's interested in Tesla (TSLA). What's your assessment?"
            ),
            "description": "Aggressive investor + high volatility stock (expect: clear match)",
        },
        {
            "prompt": (
                "Is Tesla (TSLA) appropriate for a conservative investor? "
                "The client wants capital preservation above all else."
            ),
            "description": "Conservative investor + high volatility stock (expect: not suitable)",
        },
        {
            "prompt": (
                "A moderate risk client is considering Google (GOOGL). "
                "Can you assess suitability and pull the current price?"
            ),
            "description": "Moderate investor + medium volatility (expect: clear match with price)",
        },
    ]

    print(f"Running {len(test_cases)} risk assessment tests...")
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
                session_prefix="risk-test",
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
    print("All risk assessment tests completed!")
    print()
    print("Next steps:")
    print("  - Review Lambda execution logs:")
    print(f"      aws logs tail /aws/lambda/{lambda_name} --follow")
    print("  - Try other tickers: MSFT, NVDA, AMZN, META")
    print("  - Proceed to Module 4 to add the market calendar MCP server")
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
