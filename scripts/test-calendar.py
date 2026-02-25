#!/usr/bin/env python3
"""
AWS AgentCore Workshop: MarketPulse - MCP Market Calendar Test Script

Tests the MarketPulse agent's ability to query market holiday information
via the Gateway MCP Server target (Market Calendar MCP server).

This script requires Module 4 to be deployed:
  - enable_gateway = true
  - enable_mcp_target = true
"""

import json
import subprocess
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
        output_name:   Name of the output to retrieve
        terraform_dir: Path to the terraform directory

    Returns:
        Output value as string

    Raises:
        RuntimeError: If output retrieval fails
    """
    try:
        result = subprocess.run(
            ["terraform", "output", "-raw", output_name],
            cwd=terraform_dir,
            capture_output=True,
            text=True,
            check=True,
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
        chunk_text = chunk.decode("utf-8")
        response_text.append(chunk_text)
    return response_text


def invoke_agent(
    runtime_arn: str,
    endpoint_name: str,
    prompt: str,
    region: str = "ap-southeast-2",
) -> dict[str, Any]:
    """
    Invoke the AgentCore Runtime with a prompt.

    Args:
        runtime_arn:   ARN of the AgentCore Runtime
        endpoint_name: Name of the runtime endpoint
        prompt:        User prompt to send to agent
        region:        AWS region

    Returns:
        Agent response dictionary
    """
    client = boto3.client("bedrock-agentcore", region_name=region)

    # Minimum session ID length required by AgentCore Runtime is 33 characters
    session_id = f"calendar-test-session-{uuid.uuid4()}"

    payload = json.dumps({"prompt": prompt}).encode()

    print(f"  Session ID: {session_id}")
    print()

    response = client.invoke_agent_runtime(
        agentRuntimeArn=runtime_arn,
        runtimeSessionId=session_id,
        payload=payload,
    )

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
        "content_type": content_type,
    }


def main() -> int:
    """Main test execution."""

    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    terraform_dir = project_root / "terraform"

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
            result = invoke_agent(runtime_arn, endpoint_name, test["prompt"])

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
