#!/usr/bin/env python3
"""
AWS AgentCore Workshop: MarketPulse - Agent Test Script

Tests the deployed MarketPulse agent by sending a simple query
and verifying it responds correctly.
"""

import sys
from pathlib import Path

# Import shared test utilities
from test_utils import get_terraform_output, invoke_agent, get_project_paths


def main() -> int:
    """Main test execution."""

    project_root, terraform_dir = get_project_paths()
    
    print("AWS AgentCore Workshop: Testing MarketPulse Agent")
    print("=" * 60)
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
        print(f"✓ Runtime ARN: {runtime_arn}")
        print(f"✓ Endpoint Name: {endpoint_name}")
        print()
    except RuntimeError as e:
        print(f"Error: {e}")
        print()
        print("Make sure you have:")
        print("1. Deployed the infrastructure with 'terraform apply'")
        print("2. Run 'terraform apply' after adding the new outputs")
        return 1
    
    # Test prompt
    test_prompt = "Hello! Can you introduce yourself as MarketPulse?"
    
    print(f"Sending test prompt: {test_prompt}")
    print()
    
    # Invoke agent
    try:
        result = invoke_agent(
            runtime_arn=runtime_arn,
            endpoint_name=endpoint_name,
            prompt=test_prompt,
            session_prefix="agent-test",
        )
        
        print("Agent Response:")
        print("-" * 60)
        print(result["response"])
        print("-" * 60)
        print()
        print(f"Session ID: {result['session_id']}")
        print(f"Request ID: {result['response_id']}")
        print(f"Content Type: {result['content_type']}")
        print()
        print("✓ Agent test successful!")
        return 0
        
    except Exception as e:
        print(f"Error invoking agent: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())