#!/usr/bin/env python3
"""
AWS AgentCore Workshop: MarketPulse - Stock Price Test Script

Tests the MarketPulse agent's ability to retrieve live stock prices
via the Gateway HTTP target (Finnhub API).

This script requires Module 2 to be deployed (enable_gateway and enable_http_target).
"""

import sys
import time
from pathlib import Path

# Import shared test utilities
from test_utils import get_terraform_output, invoke_agent, get_project_paths


def main() -> int:
    """Main test execution."""

    project_root, terraform_dir = get_project_paths()
    terraform_dir = project_root / "terraform"
    
    print("AWS AgentCore Workshop: Testing Stock Price Tool (Module 2)")
    print("=" * 70)
    print()
    
    # Check Terraform directory exists
    if not terraform_dir.exists():
        print(f"Error: Terraform directory not found at {terraform_dir}")
        return 1
    
    # Get runtime ARN and endpoint name from Terraform outputs
    print("Retrieving agent configuration from Terraform outputs...")
    try:
        runtime_arn = get_terraform_output("agent_runtime_arn", terraform_dir)
        endpoint_name = get_terraform_output("agent_endpoint_name", terraform_dir)
        gateway_id = get_terraform_output("gateway_id", terraform_dir)
        
        print(f"✓ Runtime ARN: {runtime_arn}")
        print(f"✓ Endpoint Name: {endpoint_name}")
        print(f"✓ Gateway ID: {gateway_id}")
        print()
        
        # Check if Gateway is enabled
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
            return 1
            
    except RuntimeError as e:
        print(f"Error: {e}")
        print()
        print("Make sure you have:")
        print("1. Enabled Gateway in terraform.tfvars (enable_gateway = true)")
        print("2. Deployed with 'terraform apply'")
        print("3. Rebuilt the agent with './scripts/build-agent.sh'")
        return 1
    
    # Test stock price queries
    test_prompts = [
        {
            "prompt": "What is the current price of Apple stock (AAPL)?",
            "description": "Single stock price query"
        },
        {
            "prompt": "Can you compare the current prices of Apple (AAPL) and Microsoft (MSFT)?",
            "description": "Multi-stock comparison"
        },
        {
            "prompt": "What's the trading range for Tesla (TSLA) today?",
            "description": "Stock trading range query"
        }
    ]
    
    print("Running stock price tests...")
    print()
    
    for i, test in enumerate(test_prompts, 1):
        print(f"Test {i}/{len(test_prompts)}: {test['description']}")
        print(f"Query: {test['prompt']}")
        print()
        
        try:
            result = invoke_agent(
                runtime_arn=runtime_arn,
                endpoint_name=endpoint_name,
                prompt=test['prompt'],
                session_prefix="stock-test",
            )
            
            print("Agent Response:")
            print("-" * 70)
            print(result["response"])
            print("-" * 70)
            print()
            
            # Brief pause between queries to respect API rate limits
            if i < len(test_prompts):
                print("Waiting 2 seconds before next query...")
                print()
                time.sleep(2)
                
        except Exception as e:
            print(f"Error invoking agent: {e}")
            import traceback
            traceback.print_exc()
            print()
            return 1
    
    print()
    print("=" * 70)
    print("✓ All stock price tests completed successfully!")
    print()
    print("Next steps:")
    print("- Check CloudWatch Logs to see Gateway tool invocations")
    print("- Try querying other stock tickers (GOOGL, AMZN, NVDA, etc.)")
    print("- Proceed to Module 3 to add Lambda risk scoring")
    print()
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
