#!/usr/bin/env bash
set -euo pipefail

# AWS AgentCore Workshop: MarketPulse - MCP Server Build Script (DEPRECATED)
# This script now calls the unified build-container.sh script.
# Use 'build-container.sh mcp' directly for new workflows.

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Call unified build script
exec "${SCRIPT_DIR}/build-container.sh" mcp "$@"
