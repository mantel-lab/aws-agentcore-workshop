#!/usr/bin/env python3
"""
AWS AgentCore Workshop: MarketPulse - Stock Price Test Script

Tests the MarketPulse agent's ability to retrieve live stock prices
via the Gateway HTTP target (Finnhub API).

This script requires Module 2 to be deployed (enable_gateway and enable_http_target).
"""

import json
import sys
import time
import uuid
from pathlib import Path
from typing import Any

import boto3


def get_terraform_output(output_name: str, terraform_dir: Path) -> str:
    """
    Retrieve a Terraform output value.
    
    Args:
        output_name: Name of the output to retrieve
        terraform_dir: Path to terraform directory
        
    Returns:
        Output value as string
        
    Raises:
        RuntimeError: If output retrieval fails
    """
    import subprocess
    
    try:
        result = subprocess.run(
            ["terraform", "output", "-raw", output_name],
            cwd=terraform_dir,
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        raise RuntimeError(
            f"Failed to get Terraform output '{output_name}': {e.stderr}"
        ) from e


def process_streaming_response(response: dict) -> list[str]:
    """
    Process text/event-stream response from agent.
    
    Args:
        response: Response dictionary from invoke_agent_runtime
        
    Returns:
        List of response text chunks
    """
    response_text = []
    for line in response["response"].iter_lines(chunk_size=10):
        if line:
            line = line.decode("utf-8")
            if line.startswith("data: "):
                line = line[6:]
                response_text.append(line)
    return response_text


def process_json_response(response: dict) -> list[str]:
    """
    Process application/json response from agent.
    
    Args:
        response: Response dictionary from invoke_agent_runtime
        
    Returns:
        List of response text chunks
    """
    response_text = []
    for chunk in response.get("response", []):
        chunk_text = chunk.decode('utf-8')
        response_text.append(chunk_text)
    return response_text


def invoke_agent(
    runtime_arn: str,
    endpoint_name: str,
    prompt: str,
    region: str = "ap-southeast-2"
) -> dict[str, Any]:
    """
    Invoke the AgentCore Runtime with a prompt.
    
    Args:
        runtime_arn: ARN of the AgentCore Runtime
        endpoint_name: Name of the runtime endpoint
        prompt: User prompt to send to agent
        region: AWS region
        
    Returns:
        Agent response as dictionary
    """
    # Use bedrock-agentcore client
    client = boto3.client("bedrock-agentcore", region_name=region)
    
    # Generate unique session ID (minimum 33 characters required)
    session_id = f"stock-test-session-{uuid.uuid4()}"
    
    # Prepare JSON payload as bytes
    payload = json.dumps({"prompt": prompt}).encode()
    
    print(f"Invoking agent runtime...")
    print(f"  Session ID: {session_id}")
    print()
    
    # Invoke the agent runtime
    response = client.invoke_agent_runtime(
        agentRuntimeArn=runtime_arn,
        runtimeSessionId=session_id,
        payload=payload
    )
    
    # Process response based on content type
    content_type = response.get("contentType", "")
    
    if "text/event-stream" in content_type:
        response_text = process_streaming_response(response)
    elif content_type == "application/json":
        response_text = process_json_response(response)
    else:
        response_text = [str(response)]
    
    full_response = "\n".join(response_text) if response_text else json.dumps(response)
    
    return {
        "response": full_response,
        "session_id": session_id,
        "response_id": response.get("ResponseMetadata", {}).get("RequestId"),
        "content_type": content_type
    }


def main() -> int:
    """Main test execution."""
    
    # Get script directory and project root
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
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
            result = invoke_agent(runtime_arn, endpoint_name, test['prompt'])
            
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
