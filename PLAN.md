# Cloud Fun Facts — IaC Deployment Plan

## Overview

Migrate Claude Fun Facts project from the current AWS account to a new AWS account using Terraform. No AWS Console interaction required.

## Current Infrastructure (eu-central-1)

| Resource | Name | Key Properties |
|---|---|---|
| DynamoDB Table | `CloudFacts` | PK: `FactID` (S), PAY_PER_REQUEST, 15 items |
| Lambda Function | `CloudFunFacts` | Python 3.13, 128MB, 20s timeout, Bedrock + DynamoDB |
| API Gateway v2 | `FunfactsAPI` | HTTP API, `GET /funfact` → Lambda proxy, `$default` stage |
| IAM Role | `CloudFunFacts-role` | LambdaBasicExecution + DynamoDBReadOnly + BedrockFullAccess |
| CloudWatch Log Group | `/aws/lambda/CloudFunFacts` | Text format |
| Amplify App | `CloudFunFacts` | WEB platform, `staging` branch, manual deploy, SPA rule |

## Terraform Project Structure

```
claude-fun-facts/
├── main.tf              # All infrastructure (DynamoDB, Lambda, API Gateway, Amplify, IAM)
├── lambda/
│   └── lambda_function.py  # Exact copy of the deployed Lambda code
├── website/
│   └── index.html       # Frontend (API URL placeholder injected by deploy script)
├── deploy-amplify.sh    # Script: inject API URL → zip → upload to Amplify
├── README.md            # Setup & usage guide
├── PLAN.md              # This file
└── .gitignore
```

## Implementation Steps

1. **terraform init** — initialize providers (aws, archive)
2. **terraform plan** — review what will be created
3. **terraform apply** — create:
   - DynamoDB table `CloudFacts` + 15 seed items (idempotent via `for_each`)
   - IAM role with scoped policies (CloudWatch, DynamoDB read, Bedrock invoke)
   - CloudWatch log group
   - Lambda function (zipped from `lambda/` directory)
   - API Gateway HTTP API with `GET /funfact` route → Lambda integration
   - Lambda permission for API Gateway invocation
   - Amplify app + `staging` branch (no Git repo — manual deploy)
4. **deploy-amplify.sh** — deploy website:
   - Read API URL from Terraform output
   - Inject into `index.html` (replace `{{API_GATEWAY_URL}}`)
   - Zip website files
   - `aws amplify create-deployment` → upload zip → `start-deployment`
   - Wait for SUCCEED status
   - Print final URLs

## Key Design Decisions

- **Single `main.tf`**: Everything in one file for simplicity. Easy to read, copy, modify.
- **No external modules**: Self-contained, no registry dependencies beyond providers.
- **DynamoDB seed via `aws_dynamodb_table_item`**: Items are managed by Terraform state, idempotent.
- **Scoped IAM policies**: Instead of broad managed policies (AmazonDynamoDBReadOnlyAccess, AmazonBedrockFullAccess), permissions are scoped to specific resources where possible.
- **Amplify manual deploy**: Terraform creates the app + branch; `deploy-amplify.sh` handles the deploy job (Terraform can't do this natively).
- **API URL placeholder**: `index.html` uses `{{API_GATEWAY_URL}}` which is replaced by the deploy script.
- **Region configurable**: Default `eu-central-1`, overridable via `-var`.
