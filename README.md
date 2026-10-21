# ☁️ Cloud Fun Facts

A serverless web app that serves random cloud computing fun facts, enhanced with AI via Amazon Bedrock. The app fetches a random fact from DynamoDB, sends it to a Bedrock LLM to make it witty and engaging, and returns it to a static website hosted on AWS Amplify.

## Architecture

```
                    ┌─────────────┐
  User Browser  ──►  │   Amplify    │  (static index.html)
                    │   Hosting     │
                    └──────┬──────┘
                           │ fetch(GET /funfact)
                           ▼
                    ┌─────────────┐
                    │  API Gateway │  (HTTP API v2)
                    │  /funfact     │
                    └──────┬──────┘
                           │ AWS_PROXY
                           ▼
                    ┌─────────────┐    ┌───────────┐
                    │   Lambda     │──►│  Bedrock   │
                    │  (Python)     │    │  (MiniMax)  │
                    └──────┬──────┘    └───────────┘
                           │ scan()
                           ▼
                    ┌─────────────┐
                    │  DynamoDB     │
                    │  CloudFacts   │  (15 seed items)
                    └─────────────┘
```

**Request flow:** User clicks "Get a Fun Fact" → Amplify-hosted page calls API Gateway → API Gateway triggers Lambda → Lambda scans DynamoDB for a random fact → Lambda sends the fact to Bedrock to make it fun → Lambda returns the witty fact as JSON → the page displays it.

## What This Project Creates

| Resource | Name | Notes |
|---|---|---|
| DynamoDB Table | `CloudFacts` | PAY_PER_REQUEST, PK: `FactID` (S) |
| DynamoDB Items | 15 facts | Pre-seeded cloud computing facts |
| IAM Role | `CloudFunFacts-role` | Lambda assume + CloudWatch + DynamoDB read + Bedrock invoke |
| CloudWatch Log Group | `/aws/lambda/CloudFunFacts` | 14-day retention |
| Lambda Function | `CloudFunFacts` | Python 3.13, 128MB, 20s timeout |
| API Gateway v2 | `FunfactsAPI` | HTTP API, `GET /funfact` → Lambda |
| Amplify App | `CloudFunFacts` | WEB platform, SPA redirect, manual deploy |

## Project Structure

```
claude-fun-facts/
├── main.tf              # All AWS infrastructure (DynamoDB, Lambda, API Gateway, Amplify, IAM)
├── lambda/
│   └── lambda_function.py  # Lambda handler — scans DynamoDB, calls Bedrock, returns JSON
├── website/
│   └── index.html       # Static frontend — fetches a fun fact from the API
├── deploy-amplify.sh    # Deploys the website to Amplify (no Git repository needed)
├── README.md            # You are here
├── PLAN.md              # Architecture decisions & design notes
└── .gitignore
```

---

## Prerequisites (What You Need Before Starting)

### 1. An AWS Account

You need an AWS account with enough permissions to create IAM roles, Lambda functions, API Gateway, DynamoDB tables, and Amplify apps. An admin-level user or role is simplest.

### 2. Install Terraform

| OS | Command |
|---|---|
| macOS (Homebrew) | `brew install opentofu` (open-source Terraform fork) or [download Terraform](https://developer.hashicorp.com/terraform/downloads) |
| Linux | [Download from HashiCorp](https://developer.hashicorp.com/terraform/downloads) |
| Windows | [Download from HashiCorp](https://developer.hashicorp.com/terraform/downloads) |

Verify it works:

```bash
terraform version
# or if you installed opentofu:
tofu version
```

> **Note:** This guide uses `terraform` commands. If you installed OpenTofu, replace `terraform` with `tofu` in every command.

### 3. Install the AWS CLI

| OS | Command |
|---|---|
| macOS | `brew install awscli` |
| Linux | `pip install awscli` or see [AWS docs](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| Windows | [AWS CLI installer](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |

### 4. Configure AWS CLI with Your Credentials

Run this and follow the prompts:

```bash
aws configure
```

You'll need:
- **AWS Access Key ID** — from your IAM user in the AWS Console (IAM → Users → your user → Security credentials)
- **AWS Secret Access Key** — created when you make the access key
- **Default region name** — e.g. `eu-central-1` (Frankfurt), `us-east-1` (N. Virginia)
- **Default output format** — type `json`

Verify it works:

```bash
aws sts get-caller-identity
```

You should see your account ID and user ARN. If this fails, your credentials aren't configured correctly.

### 5. Enable Bedrock Model Access (Important!)

The Lambda function calls Amazon Bedrock with the `minimax.minimax-m2.1` model. Before deploying, you must enable this model in your AWS account:

1. Go to the AWS Console → **Amazon Bedrock**
2. On the left sidebar, click **Model access**
3. Click **Manage model access**
4. Find **MiniMax M2.1** and check the box
5. Click **Request model access**
6. Wait for the status to change to **Access granted** (usually a few minutes)

Without this step, the Lambda function will run but the Bedrock call will fail — the API will return the raw DynamoDB fact without the AI enhancement.

---

## Step-by-Step: From Clone to Live Website

### Step 1 — Clone the Repository

```bash
git clone https://github.com/<your-username>/claude-fun-facts.git
cd claude-fun-facts
```

### Step 2 — (Optional) Customize Variables

The defaults work out-of-the-box, but if you want to change the region, resource names, or Amplify branch, you have two options:

**Option A: Command-line flags (quick, one-off)**

```bash
terraform apply -var="aws_region=us-east-1" -var="project_name=MyFunFacts"
```

**Option B: A `terraform.tfvars` file (persistent, recommended for customization)**

Create a file called `terraform.tfvars` in the project root:

```bash
cat > terraform.tfvars << 'EOF'
aws_region          = "us-east-1"
project_name        = "MyFunFacts"
amplify_branch_name = "main"
EOF
```

Available variables:

| Variable | Default | What It Does |
|---|---|---|
| `aws_region` | `eu-central-1` | AWS region where all resources are created |
| `project_name` | `CloudFunFacts` | Prefix for all resource names (Lambda name, IAM role, etc.) |
| `amplify_branch_name` | `staging` | Amplify branch name (acts as the production branch) |

> **Note:** `terraform.tfvars` is in `.gitignore` so your customizations won't be committed. If you skip this step, the defaults are fine.

### Step 3 — Initialize Terraform

This downloads the AWS provider and the archive provider (used to zip the Lambda code):

```bash
terraform init
```

Expected output: `Terraform has been successfully initialized!`

### Step 4 — Preview What Will Be Created

This shows you a plan of every resource Terraform will create, without making any changes:

```bash
terraform plan
```

Review the output. You should see ~22 resources being created:
- 1 DynamoDB table + 15 table items
- 1 IAM role + 3 inline policies + 1 assume role policy document
- 1 CloudWatch log group
- 1 Lambda function + 1 archive file
- 1 API Gateway API + 1 integration + 1 route + 1 stage + 1 Lambda permission
- 1 Amplify app + 1 Amplify branch

If everything looks good, proceed to the next step.

### Step 5 — Deploy All Infrastructure

This creates everything in your AWS account:

```bash
terraform apply
```

Type `yes` when prompted to confirm. This takes about 1–2 minutes.

When it finishes, you'll see outputs like:

```
api_gateway_url      = "https://abc123.execute-api.eu-central-1.amazonaws.com/funfact"
amplify_app_id       = "d4x7m9k2swd6"
amplify_default_domain = "https://d4x7m9k2swd6.amplifyapp.com"
amplify_branch_name  = "staging"
lambda_function_name = "CloudFunFacts"
dynamodb_table_name   = "CloudFacts"
iam_role_arn          = "arn:aws:iam::123456789012:role/CloudFunFacts-role"
```

Copy these down — you'll need the API URL and Amplify info in the next step.

### Step 6 — Test the API

Before deploying the website, verify the backend works:

```bash
# Get the API URL from Terraform output
API_URL=$(terraform output -raw api_gateway_url)

# Call the API
curl "$API_URL"
```

You should get a JSON response like:

```json
{"fact": "Did you know? AWS S3 launched way back in 2006 — making it older than the iPhone!"}
```

If you see a fact (possibly different wording — Bedrock rewrites it each time), the backend is working. If you see `{"fact": "AWS S3 was one of the very first AWS services, launched in 2006."}` (the raw fact without AI enhancement), it means Bedrock model access isn't enabled yet — go back to Prerequisites step 5.

### Step 7 — Deploy the Website to Amplify

The Terraform created the Amplify app and branch, but the actual website files need to be uploaded separately. The `deploy-amplify.sh` script handles this automatically:

```bash
./deploy-amplify.sh
```

What the script does:
1. Reads the API Gateway URL from Terraform outputs
2. Injects it into `website/index.html` (replaces the `{{API_GATEWAY_URL}}` placeholder)
3. Zips the website files
4. Uploads the zip to Amplify via the AWS CLI
5. Starts the deployment and waits for it to complete

When it finishes, you'll see:

```
✅ Amplify deployment succeeded!
Website URL: https://d4x7m9k2swd6.amplifyapp.com
```

### Step 8 — Open Your Website

Open the `Website URL` from the script output in your browser. Click **Get a Fun Fact** — you should see a witty, AI-enhanced cloud computing fact.

---

## Common Tasks After Initial Deployment

### Change the Fun Facts

The 15 seed facts are defined in `main.tf` in the `locals` block (search for `fun_facts`). Edit any fact text or add new ones, then:

```bash
terraform apply
```

### Update the Lambda Code

Edit `lambda/lambda_function.py`, then:

```bash
terraform apply
```

Terraform automatically re-zips the code and updates the Lambda function.

### Redeploy the Website

If you changed `website/index.html` (CSS, layout, text), redeploy to Amplify:

```bash
./deploy-amplify.sh
```

### Change the AWS Region

If you want to deploy to a different region:

```bash
terraform apply -var="aws_region=us-east-1"
./deploy-amplify.sh
```

> **Note:** Changing the region will create all-new resources in the new region. The old resources remain in the previous region until you run `terraform destroy` against them.

---

## Troubleshooting

### `terraform init` fails with provider download error

This usually means your machine can't reach the Terraform registry. Check your internet connection and proxy settings.

### `terraform apply` fails with authentication error

Run `aws sts get-caller-identity` to verify your AWS credentials are working. If that fails, re-run `aws configure` with valid keys.

### The API returns the raw fact without AI enhancement

Bedrock model access isn't enabled. Go to AWS Console → Amazon Bedrock → Model access → enable `minimax.minimax-m2.1`. See Prerequisites step 5.

### `deploy-amplify.sh` fails with "Could not get API Gateway URL"

You need to run `terraform apply` first. The script reads outputs from Terraform state.

### The website loads but "Get a Fun Fact" shows an error

Open your browser's developer tools (F12) → Network tab → click the button → check if the API call is failing. Common causes:
- API Gateway URL not injected (re-run `deploy-amplify.sh`)
- CORS error (the Lambda already has CORS headers, so this shouldn't happen — if it does, check that `terraform apply` completed successfully)

### `terraform destroy` fails

This can happen if Amplify has an active deployment. Wait a few minutes and try again, or delete the Amplify app from the AWS Console first, then run `terraform destroy`.

---

## Cleanup (Destroy Everything)

To remove all AWS resources created by this project:

```bash
terraform destroy
```

Type `yes` to confirm. This deletes the DynamoDB table (and all data), Lambda function, API Gateway, IAM role, CloudWatch log group, and Amplify app. This is irreversible.


Clean-up Steps on Console

To avoid ongoing AWS charges, remember to delete the resources you created:

    Amplify App
        Go to AWS Amplify Console
        Select your app → Actions → Delete App
    API Gateway
        Go to API Gateway Console
        Select your FunfactsAPI → Actions → Delete
    Lambda Function(s)
        Go to Lambda Console
        Delete functions you created (e.g., CloudFunFacts)
        Clean up associated log groups in CloudWatch Logs (/aws/lambda/...)
    DynamoDB Table
        Go to DynamoDB Console
        Select the CloudFacts table → Actions → Delete table
    IAM Role (Optional)
        Go to IAM > Roles
        Delete the custom role created for your Lambda (e.g., CloudFunFacts-role-xyz)
    CloudWatch Logs
        Go to CloudWatch > Log groups
        Delete Lambda function log groups (they start with /aws/lambda/)


---


