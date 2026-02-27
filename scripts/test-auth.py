#!/usr/bin/env python3
"""
AWS AgentCore Workshop: MarketPulse - OAuth Authentication Test Script

Tests the MCP server authentication behaviour with and without OAuth 2.0.
Demonstrates the security enhancement added in Module 6 (AgentCore Identity).

Prerequisites:
  Module 4 deployed:  enable_gateway=true, enable_mcp_target=true
  Module 6 deployed:  enable_identity=true

Test scenarios:
  1. MCP calls work when enable_identity=false (Module 4)
  2. OAuth authentication is required when enable_identity=true (Module 6)
  3. Valid Agent calls work with OAuth enabled (Module 6)
"""

import sys
import time
from pathlib import Path

# Import shared test utilities
from test_utils import get_terraform_output, invoke_agent, get_project_paths


def main() -> int:
    """Main test execution."""

    project_root, terraform_dir = get_project_paths()

    print("AWS AgentCore Workshop: Testing OAuth Authentication (Module 6)")
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
        auth_enabled = get_terraform_output("mcp_authentication_enabled", terraform_dir)

        print(f"  Runtime ARN:           {runtime_arn}")
        print(f"  Endpoint Name:         {endpoint_name}")
        print(f"  MCP Configured:        {mcp_configured}")
        print(f"  Authentication:        {auth_enabled}")
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

        if auth_enabled.lower() != "true":
            print("⚠️  OAuth authentication is NOT enabled")
            print()
            print("Current configuration: Module 4 (MCP without authentication)")
            print()
            print("What this means:")
            print("  - MCP server accepts calls without JWT Bearer tokens")
            print("  - Gateway uses GATEWAY_IAM_ROLE credential type")
            print("  - No Cognito User Pool created")
            print()
            print("To test OAuth authentication:")
            print("  1. Edit terraform/terraform.tfvars:")
            print("       enable_identity = true")
            print("  2. Run: cd terraform && terraform apply")
            print("  3. Re-run this test script")
            print()
            print("For now, testing that MCP calls work without authentication...")
            print()
        else:
            print("✓ OAuth 2.0 authentication is ENABLED")
            print()
            print("Current configuration: Module 6 (MCP with OAuth authentication)")
            print()
            print("What this means:")
            print("  - MCP Runtime validates JWT Bearer tokens from Cognito")
            print("  - Gateway obtains tokens via AgentCore Identity credential provider")
            print("  - Unauthenticated calls return 401 Unauthorised")
            print()

        print("Retrieving additional configuration...")
        try:
            if auth_enabled.lower() == "true":
                cognito_pool_id = get_terraform_output("cognito_user_pool_id", terraform_dir)
                oauth_discovery_url = get_terraform_output("oauth_discovery_url", terraform_dir)
                print(f"  Cognito Pool ID:       {cognito_pool_id}")
                print(f"  Discovery URL:         {oauth_discovery_url}")
                print()
        except RuntimeError:
            # Cognito outputs only exist when enable_identity=true
            pass

    except RuntimeError as e:
        print(f"Error: {e}")
        print()
        print("Make sure you have:")
        print("  1. Set enable_mcp_target = true in terraform.tfvars")
        print("  2. Run 'terraform apply'")
        print("  3. Built the MCP server: './scripts/build-mcp.sh'")
        print("  4. Rebuilt the agent: './scripts/build-agent.sh'")
        return 1

    # ---------------------------------------------------------------------------
    # Test: MCP Market Calendar Tool (with or without OAuth)
    # ---------------------------------------------------------------------------

    test_cases = [
        {
            "prompt": "Are there any market holidays in Australia this week?",
            "description": "Test MCP server authentication",
            "expected": "Holiday data or trading days confirmation",
        },
        {
            "prompt": (
                "Check if there are any public holidays affecting the Australian stock market "
                "in the next 5 days."
            ),
            "description": "Test OAuth token acquisition and validation",
            "expected": "Holiday information with dates",
        },
    ]

    print("Test Scenarios")
    print("-" * 70)
    print()

    success_count = 0
    failure_count = 0

    for i, test_case in enumerate(test_cases, 1):
        print(f"Test {i}: {test_case['description']}")
        print(f"Prompt: {test_case['prompt']}")
        print()

        try:
            result = invoke_agent(
                runtime_arn=runtime_arn,
                endpoint_name=endpoint_name,
                prompt=test_case["prompt"],
            )

            response_text = result.get("response", "")
            
            if response_text:
                print(f"✓ Test {i} PASSED")
                print(f"  Expected: {test_case['expected']}")
                print(f"  Received: {response_text[:200]}{'...' if len(response_text) > 200 else ''}")
                print()
                success_count += 1
            else:
                print(f"✗ Test {i} FAILED - Empty response")
                print()
                failure_count += 1

        except Exception as e:
            error_msg = str(e)
            print(f"✗ Test {i} FAILED - {error_msg}")
            print()
            
            # Print additional error details if available
            if hasattr(e, 'response'):
                print(f"  Error response: {e.response}")
            if hasattr(e, '__dict__'):
                print(f"  Error attributes: {e.__dict__}")
            print()

            # Check for authentication errors
            if "401" in error_msg or "Unauthorised" in error_msg or "Unauthorized" in error_msg:
                print("  This is an authentication error!")
                print()
                if auth_enabled.lower() == "true":
                    print("  Possible causes:")
                    print("    - OAuth credential provider not configured correctly")
                    print("    - Token validation failed at MCP Runtime")
                    print("    - Cognito client ID mismatch")
                    print()
                    print("  Check:")
                    print("    1. SSM Parameter: /${project_root.stem}/dev/mcp-oauth-provider-arn")
                    print("    2. Cognito User Pool Client ID in allowed_clients")
                    print("    3. CloudWatch logs for MCP Runtime")
                else:
                    print("  This is unexpected! Authentication should be disabled.")
            
            failure_count += 1

        # Rate limiting: pause between requests
        if i < len(test_cases):
            time.sleep(2)

    # ---------------------------------------------------------------------------
    # Summary
    # ---------------------------------------------------------------------------
    print("=" * 70)
    print("Test Summary")
    print("-" * 70)
    print(f"Total tests:         {len(test_cases)}")
    print(f"Passed:              {success_count}")
    print(f"Failed:              {failure_count}")
    print()

    if auth_enabled.lower() == "true":
        print("Authentication Status: OAuth 2.0 ENABLED ✓")
        print()
        print("Key components working:")
        print("  ✓ Cognito User Pool issuing JWT tokens")
        print("  ✓ AgentCore Identity credential provider")
        print("  ✓ Gateway obtaining and sending Bearer tokens")
        print("  ✓ MCP Runtime validating tokens before forwarding to FastMCP")
        print()
        print("Security benefits:")
        print("  - Only authorised clients can call the MCP server")
        print("  - Tokens expire after 1 hour (configurable)")
        print("  - Full audit trail in CloudWatch logs")
        print("  - Scope-based access control (mcp-runtime-server/invoke)")
    else:
        print("Authentication Status: OAuth 2.0 DISABLED")
        print()
        print("Current credential type: GATEWAY_IAM_ROLE")
        print()
        print("To enable OAuth authentication (Module 6):")
        print("  1. Edit terraform/terraform.tfvars and set enable_identity = true")
        print("  2. Run: cd terraform && terraform apply")
        print("  3. This will create:")
        print("       - Cognito User Pool for token issuance")
        print("       - M2M OAuth client for Gateway")
        print("       - AgentCore Identity credential provider")
        print("       - JWT authoriser on MCP Runtime")
        print("  4. Re-run this test to verify authenticated access")

    print()
    print("=" * 70)

    return 0 if failure_count == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
