"""
AWS AgentCore Workshop: Shared Test Utilities

Common functions used across all test scripts. Eliminates code duplication
and provides a single source of truth for test infrastructure.
"""

import json
import subprocess
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
    session_prefix: str = "test-session",
    region: str = "ap-southeast-2",
) -> dict[str, Any]:
    """
    Invoke the AgentCore Runtime with a prompt.

    Args:
        runtime_arn: ARN of the AgentCore Runtime
        endpoint_name: Name of the runtime endpoint
        prompt: User prompt to send to agent
        session_prefix: Prefix for session ID (helps identify test type in logs)
        region: AWS region

    Returns:
        Agent response dictionary with keys:
            - response: Full response text
            - session_id: Session ID used
            - response_id: AWS request ID
            - content_type: Response content type
    """
    client = boto3.client("bedrock-agentcore", region_name=region)

    # Minimum session ID length required by AgentCore Runtime is 33 characters
    session_id = f"{session_prefix}-{uuid.uuid4()}"

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


def get_project_paths() -> tuple[Path, Path]:
    """
    Get standard project paths for test scripts.

    Returns:
        Tuple of (project_root, terraform_dir)
    """
    # Assumes test scripts are in scripts/ directory
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    terraform_dir = project_root / "terraform"
    return project_root, terraform_dir
