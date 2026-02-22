# MarketPulse Terraform Configuration

Infrastructure as Code for the AWS AgentCore Workshop MarketPulse agent.

## Prerequisites

### 1. Install Terraform

**macOS (Homebrew):**
```bash
brew install terraform
```

**Linux:**
```bash
wget https://releases.hashicorp.com/terraform/1.10.0/terraform_1.10.0_linux_amd64.zip
unzip terraform_1.10.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

**Verify installation:**
```bash
terraform version
```

### 2. Configure AWS Credentials

Ensure your AWS credentials are configured:
```bash
aws configure
```

Or use environment variables:
```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

### 3. Verify Bedrock Model Access

Ensure you have access to the Bedrock model:
```bash
aws bedrock list-foundation-models --region us-east-1 \
  --by-provider anthropic
```

## Quick Start

### Phase 1: Foundation (Current)

1. **Copy example configuration:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit terraform.tfvars:**
   ```bash
   # Update these values
   project_name = "marketpulse"
   environment  = "workshop"
   aws_region   = "us-east-1"
   
   # All feature flags should be false in Phase 1
   enable_gateway       = false
   enable_http_target   = false
   enable_lambda_target = false
   enable_mcp_target    = false
   enable_memory        = false
   enable_identity      = false
   enable_observability = false
   ```

3. **Initialise Terraform:**
   ```bash
   terraform init
   ```

4. **Validate configuration:**
   ```bash
   terraform validate
   ```

5. **Preview infrastructure (dry run):**
   ```bash
   terraform plan
   ```

6. **Phase 1 creates no resources** - this is intentional. It establishes the foundation for subsequent phases.

### Phase 2: Module 1 - AgentCore Runtime Deployment

**Step-by-step deployment workflow:**

1. **Create ECR repository first:**
   ```bash
   terraform apply
   ```
   This will create the ECR repository. The runtime creation will fail initially because no container image exists yet - this is expected.

2. **Build and push the agent container:**
   ```bash
   cd ..
   ./scripts/build-agent.sh
   cd terraform
   ```
   This builds the Docker image and pushes it to the ECR repository created in step 1.

3. **Create the AgentCore Runtime:**
   ```bash
   terraform apply
   ```
   Now that the container image exists, the runtime will be created successfully.

4. **Test the deployed agent:**
   ```bash
   cd ..
   python3 scripts/test-agent.py
   cd terraform
   ```
   This sends a test prompt to verify the agent is responding correctly.

### Phase 2: Gateway + HTTP Target (Module 2)

**Gateway Implementation Note:**  
The AgentCore Gateway resources use AWS CLI commands via `null_resource` provisioners because AWSCC Terraform provider support for Gateway is still emerging. This workshop-appropriate approach ensures compatibility while AWS provider support matures.

Enable gateway features:
```bash
# In terraform.tfvars
enable_gateway     = true
enable_http_target = true
finnhub_api_key    = "your-api-key"  # Get from https://finnhub.io
```

Then deploy:
```bash
terraform plan
terraform apply
```

**What gets created:**
- AgentCore Gateway (via AWS CLI)
- S3 bucket for OpenAPI specifications
- OpenAPI spec for Finnhub stock price API
- Secrets Manager secret for Finnhub API key
- Gateway target linking the OpenAPI spec to Gateway
- IAM permissions for agent to invoke Gateway

**After deployment:**
```bash
cd ..
./scripts/build-agent.sh  # Rebuild agent with Gateway tool
python3 scripts/test-stock.py  # Test stock price queries
```

## File Structure

```
terraform/
├── README.md                    # This file
├── main.tf                      # Provider and data sources
├── variables.tf                 # Input variables
├── locals.tf                    # Computed values
├── outputs.tf                   # Output values
├── terraform.tfvars.example     # Example configuration
├── runtime.tf                   # AgentCore Runtime (Phase 2)
├── gateway.tf                   # Gateway + HTTP Target (Phase 2)
├── lambda.tf                    # Lambda Target (Phase 3)
├── mcp.tf                       # MCP Server Target (Phase 4)
├── memory.tf                    # Memory with DynamoDB (Phase 5)
├── identity.tf                  # Identity with OAuth 2.0 (Phase 6)
└── observability.tf             # Observability with Tracing (Phase 7)
```

## Feature Flags

The configuration uses feature flags to enable modules progressively:

| Flag | Phase | Module | Resources Created |
|------|-------|--------|-------------------|
| `enable_gateway` | 2 | Gateway | AgentCore Gateway |
| `enable_http_target` | 2 | HTTP Target | Secrets Manager, HTTP Gateway Target |
| `enable_lambda_target` | 3 | Lambda Target | Lambda function, IAM role, Gateway Target |
| `enable_mcp_target` | 4 | MCP Server | ECR, Runtime, Endpoint, Gateway Target |
| `enable_memory` | 5 | Memory | DynamoDB table, Memory config |
| `enable_identity` | 6 | Identity | Cognito User Pool, OAuth config |
| `enable_observability` | 7 | Observability | CloudWatch, X-Ray, Dashboard |

## Common Commands

```bash
# Initialise (download providers)
terraform init

# Validate syntax
terraform validate

# Format code
terraform fmt -recursive

# Preview changes
terraform plan

# Apply changes
terraform apply

# Show current state
terraform show

# List resources
terraform state list

# Destroy all resources (workshop cleanup)
terraform destroy
```

## Troubleshooting

### Terraform Not Found
```bash
# Install terraform (macOS)
brew install terraform

# Verify
terraform version
```

### AWS Credentials Not Configured
```bash
aws configure
# Or use environment variables
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
```

### Bedrock Model Not Available
```bash
# Check available models in your region
aws bedrock list-foundation-models --region us-east-1

# Request model access in AWS Console:
# Bedrock → Model access → Request access
```

### Resource Already Exists
```bash
# Import existing resource
terraform import <resource_type>.<resource_name> <resource_id>

# Or destroy and recreate
terraform destroy
terraform apply
```

## Cost Management

Phase 1 creates **no resources** and incurs **no costs**.

Future phases will create resources with costs:
- **Bedrock**: Pay per token (Claude 3.5 Sonnet pricing)
- **Lambda**: Free tier eligible (1M requests/month)
- **DynamoDB**: On-demand pricing (Phase 5)
- **CloudWatch**: Logs and metrics (Phase 7)

**Workshop recommendation**: Destroy resources after each session:
```bash
terraform destroy
```

## Security Notes

- `.gitignore` excludes `terraform.tfvars` (contains secrets)
- Never commit `terraform.tfvars` to version control
- Use AWS Secrets Manager for API keys (Phase 2+)
- Follow least privilege IAM policies

## Next Steps

1. Complete Phase 1 foundation (current)
2. Progress through development plan phases
3. Enable features incrementally
4. Test each phase before proceeding
5. Clean up resources after workshop

## Support

Refer to:
- [Development Plan](../DEVELOPMENT_PLAN.md)
- [Terraform Implementation Plan](../TERRAFORM_IMPLEMENTATION_PLAN.md)
- [Workshop Documentation](../docs/)