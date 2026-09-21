"""
AWS AgentCore Workshop: Shared Test Utilities

Common functions used across all test scripts. Eliminates code duplication
and provides a single source of truth for test infrastructure.

Also provides price verification helpers. An LLM will happily invent a stock
price when a tool call fails, so tests compare the numbers in the agent's answer
against a live Finnhub quote instead of assuming a non-empty response is correct.
"""

import json
import os
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from typing import Any

import boto3

FINNHUB_QUOTE_URL = "https://finnhub.io/api/v1/quote"

# Matches currency amounts such as "$182.45", "USD 1,234.50", "182.45"
_AMOUNT_PATTERN = re.compile(r"\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+\.\d+")

# Verification outcomes that mean the agent reported a price it did not retrieve
FAILURE_STATUSES = frozenset({"hallucinated", "no_price"})


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
    actor_id: str | None = None,
    session_id_override: str | None = None,
) -> dict[str, Any]:
    """
    Invoke the AgentCore Runtime with a prompt.

    Args:
        runtime_arn: ARN of the AgentCore Runtime
        endpoint_name: Name of the runtime endpoint
        prompt: User prompt to send to agent
        session_prefix: Prefix for session ID (helps identify test type in logs)
        region: AWS region
        actor_id: Actor ID for memory (optional, used when memory is enabled)
        session_id_override: Explicit session ID for memory persistence (optional)

    Returns:
        Agent response dictionary with keys:
            - response: Full response text
            - session_id: Session ID used
            - response_id: AWS request ID
            - content_type: Response content type
    """
    client = boto3.client("bedrock-agentcore", region_name=region)

    # Use provided session_id or generate one
    # Minimum session ID length required by AgentCore Runtime is 33 characters
    if session_id_override:
        session_id = session_id_override
    else:
        session_id = f"{session_prefix}-{uuid.uuid4()}"

    # Build payload with optional memory fields
    payload_dict = {"prompt": prompt}
    if actor_id:
        payload_dict["actor_id"] = actor_id
    if session_id_override:
        payload_dict["session_id"] = session_id_override

    payload = json.dumps(payload_dict).encode()

    print(f"  Session ID: {session_id}")
    if actor_id:
        print(f"  Actor ID: {actor_id}")
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


def _find_key_in_file(path: Path, pattern: str) -> str | None:
    """Return the first capture group matching pattern in path, ignoring placeholders."""
    if not path.exists():
        return None
    match = re.search(pattern, path.read_text(), re.MULTILINE)
    if not match or match.group(1).startswith("your_"):
        return None
    return match.group(1)


def load_finnhub_api_key(project_root: Path | None = None) -> str | None:
    """
    Find the Finnhub API key used by the deployed Gateway target.

    Looks at FINNHUB_API_KEY first, then .env, then terraform/terraform.tfvars.

    Returns:
        The API key, or None when no key is configured locally.
    """
    if project_root is None:
        project_root, _ = get_project_paths()

    return (
        os.environ.get("FINNHUB_API_KEY", "").strip()
        or _find_key_in_file(
            project_root / ".env", r"^\s*FINNHUB_API_KEY\s*=\s*[\"']?([^\"'\s]+)"
        )
        or _find_key_in_file(
            project_root / "terraform" / "terraform.tfvars",
            r"^\s*finnhub_api_key\s*=\s*\"([^\"]+)\"",
        )
    )


def fetch_finnhub_quote(symbol: str, api_key: str, timeout: int = 10) -> dict[str, Any]:
    """
    Fetch a live quote from Finnhub for comparison against the agent's answer.

    Returns:
        Finnhub quote payload, or {"error": "..."} when the request fails.
        The free tier rejects non-US symbols (for example ASX ".AX" tickers).
    """
    query = urllib.parse.urlencode({"symbol": symbol, "token": api_key})
    request = urllib.request.Request(f"{FINNHUB_QUOTE_URL}?{query}")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP {e.code} from Finnhub (free tier does not cover this symbol)"}
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as e:
        return {"error": f"Finnhub request failed: {e}"}


def extract_amounts(text: str) -> list[float]:
    """Extract decimal/thousand-separated numbers that could be quoted prices."""
    return [float(match.replace(",", "")) for match in _AMOUNT_PATTERN.findall(text)]


def verify_stock_price(
    response_text: str, symbol: str, api_key: str | None, tolerance_pct: float = 2.0
) -> dict[str, Any]:
    """
    Check that prices quoted for a symbol match a live Finnhub quote.

    Args:
        response_text: The agent's answer.
        symbol:        Ticker the agent was asked about.
        api_key:       Finnhub key, or None to skip verification.
        tolerance_pct: Allowed drift between the agent's figure and the live quote.

    Returns:
        dict with keys: symbol, status, detail.
        Status is one of: verified, hallucinated, no_price, unavailable, skipped.
        See FAILURE_STATUSES for the statuses that count as failures.
    """

    def result(status: str, detail: str) -> dict[str, Any]:
        return {"symbol": symbol, "status": status, "detail": detail}

    if not api_key:
        return result("skipped", "No Finnhub API key found locally")

    quote = fetch_finnhub_quote(symbol, api_key)
    live_prices = [float(quote.get(field) or 0) for field in ("c", "h", "l", "o", "pc")]
    live_prices = [price for price in live_prices if price > 0]
    amounts = extract_amounts(response_text)

    if not live_prices:
        detail = quote.get("error", "Finnhub returned a zeroed quote")
        if amounts:
            return result(
                "hallucinated", f"{detail}, but the agent still quoted figures: {amounts[:5]}"
            )
        return result("unavailable", detail)

    for amount in amounts:
        for price in live_prices:
            if abs(amount - price) <= price * tolerance_pct / 100:
                return result("verified", f"agent quoted {amount} vs live {price}")

    if not amounts:
        return result("no_price", f"No price in response; live price was {live_prices[0]}")

    return result(
        "hallucinated",
        f"Agent quoted {amounts[:5]} but live quote was {sorted(set(live_prices))}",
    )


def report_verification(results: list[dict[str, Any]]) -> bool:
    """
    Print verification results and report whether the checks passed.

    Returns:
        True when no result is a failure.
    """
    failures = [r for r in results if r["status"] in FAILURE_STATUSES]

    print("Price verification (agent answer vs live Finnhub quote):")
    for check in results:
        marker = "FAIL" if check["status"] in FAILURE_STATUSES else "ok  "
        print(f"  [{marker}] {check['symbol']}: {check['status']} - {check['detail']}")
    print()

    if failures:
        print(f"{len(failures)} check(s) failed. The agent reported prices it did not retrieve.")
        print("Check CloudWatch logs for the Gateway tool call - a failed tool call")
        print("often leads the model to answer from training data instead.")
        print()

    return not failures
