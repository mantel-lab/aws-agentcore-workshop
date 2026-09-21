#!/usr/bin/env python3
"""
AWS AgentCore Workshop: MarketPulse - Stock Price Test Script

Tests the MarketPulse agent's ability to retrieve live stock prices
via the Gateway HTTP target (Finnhub API).

The Finnhub free tier serves US-listed equities only, so the queries use US
tickers. Every price in the agent's answer is compared against a live quote
fetched directly from Finnhub - a fluent answer full of invented prices is a
failure, not a pass.

This script requires Module 2 to be deployed (enable_gateway and enable_http_target).
"""

import sys
import time
from pathlib import Path

# Import shared test utilities
from test_utils import (
    get_project_paths,
    get_terraform_output,
    invoke_agent,
    load_finnhub_api_key,
    report_verification,
    verify_stock_price,
)


TEST_PROMPTS = [
    {
        "prompt": "What is the current price of NVIDIA stock (NVDA)?",
        "description": "Single stock price query",
        "symbols": ["NVDA"],
    },
    {
        "prompt": "Can you compare the current prices of NVIDIA (NVDA) and Microsoft (MSFT)?",
        "description": "Multi-stock comparison",
        "symbols": ["NVDA", "MSFT"],
    },
    {
        "prompt": "What's the trading range for Tesla (TSLA) today?",
        "description": "Stock trading range query",
        "symbols": ["TSLA"],
    },
    {
        "prompt": "What is the current price of BHP Group (BHP.AX) on the ASX?",
        "description": "Unsupported ASX ticker (expect: agent reports data unavailable)",
        "symbols": ["BHP.AX"],
    },
]


def load_agent_config(terraform_dir: Path) -> tuple[str, str] | None:
    """
    Read the runtime ARN and endpoint name from Terraform outputs.

    Returns:
        Tuple of (runtime_arn, endpoint_name), or None when Module 2 is not deployed.
    """
    print("Retrieving agent configuration from Terraform outputs...")
    try:
        runtime_arn = get_terraform_output("agent_runtime_arn", terraform_dir)
        endpoint_name = get_terraform_output("agent_endpoint_name", terraform_dir)
        gateway_id = get_terraform_output("gateway_id", terraform_dir)
    except RuntimeError as e:
        print(f"Error: {e}")
        print()
        print("Make sure you have:")
        print("1. Enabled Gateway in terraform.tfvars (enable_gateway = true)")
        print("2. Deployed with 'terraform apply'")
        print("3. Rebuilt the agent with './scripts/build-agent.sh'")
        return None

    print(f"✓ Runtime ARN: {runtime_arn}")
    print(f"✓ Endpoint Name: {endpoint_name}")
    print(f"✓ Gateway ID: {gateway_id}")
    print()

    if not gateway_id or gateway_id == "null":
        print("Error: Gateway not deployed yet!")
        print()
        print("To enable the Gateway and HTTP target:")
        print("1. Edit terraform/terraform.tfvars:")
        print("   enable_gateway = true")
        print("   enable_http_target = true")
        print("   finnhub_api_key = \"your_api_key_here\"")
        print("2. Run: cd terraform && terraform apply")
        print("3. Rebuild agent: ./scripts/build-agent.sh")
        print("4. Wait 2-3 minutes for deployment")
        print()
        return None

    return runtime_arn, endpoint_name


def run_query(test: dict, runtime_arn: str, endpoint_name: str, api_key: str | None) -> list[dict]:
    """Send one prompt to the agent and verify every price it quotes."""
    result = invoke_agent(
        runtime_arn=runtime_arn,
        endpoint_name=endpoint_name,
        prompt=test["prompt"],
        session_prefix="stock-test",
    )

    print("Agent Response:")
    print("-" * 70)
    print(result["response"])
    print("-" * 70)
    print()

    return [
        verify_stock_price(result["response"], symbol, api_key) for symbol in test["symbols"]
    ]


def main() -> int:
    """Main test execution."""

    project_root, terraform_dir = get_project_paths()

    print("AWS AgentCore Workshop: Testing Stock Price Tool (Module 2)")
    print("=" * 70)
    print()

    if not terraform_dir.exists():
        print(f"Error: Terraform directory not found at {terraform_dir}")
        return 1

    config = load_agent_config(terraform_dir)
    if config is None:
        return 1
    runtime_arn, endpoint_name = config

    api_key = load_finnhub_api_key(project_root)
    if not api_key:
        print("Warning: no Finnhub API key found in FINNHUB_API_KEY, .env, or")
        print("terraform/terraform.tfvars. Prices cannot be verified, so this run")
        print("will not detect hallucinated prices.")
        print()

    print("Running stock price tests...")
    print()

    verification_results = []

    for i, test in enumerate(TEST_PROMPTS, 1):
        print(f"Test {i}/{len(TEST_PROMPTS)}: {test['description']}")
        print(f"Query: {test['prompt']}")
        print()

        try:
            verification_results.extend(run_query(test, runtime_arn, endpoint_name, api_key))
        except Exception as e:
            print(f"Error invoking agent: {e}")
            import traceback
            traceback.print_exc()
            print()
            return 1

        # Brief pause between queries to respect API rate limits
        if i < len(TEST_PROMPTS):
            print("Waiting 2 seconds before next query...")
            print()
            time.sleep(2)

    print()
    print("=" * 70)

    if not report_verification(verification_results):
        print("Stock price tests FAILED: the agent's prices do not match live data.")
        print()
        return 1

    print("✓ All stock price tests passed - quoted prices match live Finnhub data.")
    print()
    print("Next steps:")
    print("- Check CloudWatch Logs to see Gateway tool invocations")
    print("- Try other US tickers (AAPL, GOOGL, AMZN, JNJ, etc.)")
    print("- Proceed to Module 3 to add Lambda risk scoring")
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
