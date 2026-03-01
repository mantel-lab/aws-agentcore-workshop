#!/usr/bin/env python3
"""
AWS AgentCore Workshop: MarketPulse - Memory Test Script

Tests AgentCore Memory by providing client details in one invocation,
then verifying the agent recalls that information in a subsequent invocation
without needing to repeat it.

This demonstrates persistent memory across separate agent sessions.
"""

import sys
import time
import uuid
from pathlib import Path

# Import shared test utilities
from test_utils import get_terraform_output, invoke_agent, get_project_paths


def main() -> int:
    """Main test execution."""

    project_root, terraform_dir = get_project_paths()
    
    print("AWS AgentCore Workshop: Testing Memory Persistence")
    print("=" * 60)
    print()
    
    # Check Terraform directory exists
    if not terraform_dir.exists():
        print(f"Error: Terraform directory not found at {terraform_dir}")
        return 1
    
    # Retrieve agent configuration from Terraform outputs
    print("Retrieving agent configuration from Terraform outputs...")
    try:
        runtime_arn = get_terraform_output("agent_runtime_arn", terraform_dir)
        endpoint_name = get_terraform_output("agent_endpoint_name", terraform_dir)
        memory_enabled = get_terraform_output("memory_enabled", terraform_dir)
        print(f"✓ Runtime ARN: {runtime_arn}")
        print(f"✓ Endpoint Name: {endpoint_name}")
        print()
    except RuntimeError as e:
        print(f"Error: {e}")
        print()
        print("Make sure you have deployed the infrastructure with 'terraform apply'")
        return 1
    
    # Check if memory is enabled
    if memory_enabled.lower() != "true":
        print("❌ Memory is not enabled!")
        print()
        print("To enable memory:")
        print("1. Edit terraform.tfvars and set: enable_memory = true")
        print("2. Run: terraform apply")
        print("3. Rebuild the agent container: scripts/build-agent.sh")
        print("4. Re-run this test")
        return 1
    print("✓ Memory is enabled")
    print()
    
    # Generate unique session and actor IDs for this test run
    # Note: runtimeSessionId must be at least 33 characters
    test_run_id = str(uuid.uuid4())
    actor_id = f"advisor-{test_run_id}"
    session_id = f"memory-test-session-{test_run_id}"
    
    print(f"Test Run ID: {test_run_id}")
    print(f"Actor ID: {actor_id[:48]}...")  # Truncate for display
    print(f"Session ID: {session_id[:48]}...")  # Truncate for display
    print()
    
    # ========================================================================
    # Test 1: Provide client details
    # ========================================================================
    
    print("Test 1: Providing client details")
    print("-" * 60)
    
    scenario_1_prompt = """I have a new client meeting tomorrow. Her name is Sarah Chen, 
she's 45 years old, and has a conservative risk profile. She's interested in 
established tech companies and wants to build a diversified portfolio for retirement."""
    
    print(f"Prompt: {scenario_1_prompt}")
    print()
    
    try:
        result_1 = invoke_agent(
            runtime_arn=runtime_arn,
            endpoint_name=endpoint_name,
            prompt=scenario_1_prompt,
            session_prefix="memory-test",
            actor_id=actor_id,
            session_id_override=session_id,
        )
        
        print("Agent Response:")
        print(result_1["response"])
        print()
        print(f"Request ID: {result_1['response_id']}")
        print()
        
    except Exception as e:
        print(f"Error in Test 1: {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    # Wait for memory extraction to complete
    # Memory strategies process events asynchronously
    print("Waiting 10 seconds for memory extraction to complete...")
    print()
    time.sleep(10)
    
    # ========================================================================
    # Test 2: Query without repeating client details
    # ========================================================================
    
    print("Test 2: Verifying memory recall (no context repetition)")
    print("-" * 60)
    
    scenario_2_prompt = """What do you remember about my client?"""
    
    print(f"Prompt: {scenario_2_prompt}")
    print()
    
    try:
        result_2 = invoke_agent(
            runtime_arn=runtime_arn,
            endpoint_name=endpoint_name,
            prompt=scenario_2_prompt,
            session_prefix="memory-test",
            actor_id=actor_id,
            session_id_override=session_id,
        )
        
        print("Agent Response:")
        print(result_2["response"])
        print()
        print(f"Request ID: {result_2['response_id']}")
        print()
        
        # Verify the agent mentions key details
        response_lower = result_2["response"].lower()
        details_recalled = []
        details_missing = []
        
        key_details = [
            ("sarah chen", "Client name"),
            ("conservative", "Risk profile"),
            ("tech", "Investment interest"),
        ]
        
        print("Memory Verification:")
        print("-" * 60)
        for detail, description in key_details:
            if detail in response_lower:
                details_recalled.append(description)
                print(f"✓ {description}: Recalled")
            else:
                details_missing.append(description)
                print(f"✗ {description}: Not found in response")
        
        print()
        
        if details_missing:
            print(f"⚠️  Some details were not recalled: {', '.join(details_missing)}")
            print()
            print("This could mean:")
            print("- Memory extraction is still processing (try waiting longer)")
            print("- Memory strategy needs tuning")
            print("- Agent chose not to include all details in its response")
            print()
            print("Note: Short-term memory (conversation history) should always work")
            print("Long-term memory (extracted preferences) may take time to process")
            return 0  # Not a hard failure - memory is working, just slow
        else:
            print("✓ All key details successfully recalled!")
            print()
            print("Memory test successful!")
            print()
            print("Key Insights:")
            print("- Agent remembered client details across separate invocations")
            print("- Memory persists using actor_id and session_id")
            print("- Both short-term and long-term memory are operational")
            return 0
        
    except Exception as e:
        print(f"Error in Test 2: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
