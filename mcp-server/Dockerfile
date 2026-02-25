FROM public.ecr.aws/docker/library/python:3.11-slim

WORKDIR /app

COPY requirements.txt requirements.txt
RUN apt-get update && apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/* && \
    pip install --no-cache-dir -r requirements.txt

# Create non-root user
RUN useradd -m -u 1000 bedrock_agentcore
USER bedrock_agentcore

# AgentCore Runtime expects MCP servers at 0.0.0.0:8000/mcp
EXPOSE 8000

COPY . .

# Port 8000 is where FastMCP listens by default with streamable-http transport.
# Use a socket-level check since the MCP protocol path (/mcp) requires
# a proper JSON-RPC initialise sequence rather than a simple HTTP GET.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python3 -c "import socket; s=socket.create_connection(('localhost', 8000), timeout=2); s.close()" || exit 1

CMD ["python", "server.py"]
