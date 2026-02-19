#!/usr/bin/env python3
"""
AWS AgentCore Workshop: MarketPulse - Agent Test Script

Tests the deployed MarketPulse agent by sending a simple query
and verifying it responds correctly.
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
    print("Processing streaming response...")
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
    print("Processing JSON response...")
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
        endpoint_name: Name of the runtime endpoint (not used in bedrock-agentcore)
        prompt: User prompt to send to agent
        region: AWS region
        
    Returns:
        Agent response as dictionary
    """
    # Use bedrock-agentcore client (not bedrock-agent-runtime)
    client = boto3.client("bedrock-agentcore", region_name=region)
    
    # Generate unique session ID (minimum 33 characters required)
    session_id = f"test-session-{uuid.uuid4()}"
    
    # Prepare JSON payload as bytes
    payload = json.dumps({"prompt": prompt}).encode()
    
    print(f"Invoking agent runtime...")
    print(f"  Runtime ARN: {runtime_arn}")
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
    print(f"Response content type: {content_type}")
    
    if "text/event-stream" in content_type:
        response_text = process_streaming_response(response)
    elif content_type == "application/json":
        response_text = process_json_response(response)
    else:
        print(f"Unexpected content type, returning raw response")
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
        result = invoke_agent(runtime_arn, endpoint_name, test_prompt)
        
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