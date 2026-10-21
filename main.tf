terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Name prefix used for all resources"
  type        = string
  default     = "CloudFunFacts"
}

variable "amplify_branch_name" {
  description = "Amplify branch name (production branch)"
  type        = string
  default     = "staging"
}

# ---------------------------------------------------------------------------
# Provider
# ---------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# DynamoDB Table
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "cloud_facts" {
  name         = "CloudFacts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "FactID"

  attribute {
    name = "FactID"
    type = "S"
  }

  tags = {
    Project = var.project_name
  }
}

# ---------------------------------------------------------------------------
# DynamoDB Seed Data (15 facts)
# ---------------------------------------------------------------------------

locals {
  fun_facts = [
    { id = "1", text = "AWS S3 was one of the very first AWS services, launched in 2006." },
    { id = "2", text = "Netflix runs almost all of its infrastructure on AWS." },
    { id = "3", text = "Cloud computing can save companies up to 30% on IT costs." },
    { id = "4", text = "NASA uses AWS to store and share Mars mission data with the public." },
    { id = "5", text = "AWS has more than 200 fully featured services today." },
    { id = "6", text = "The 'cloud' doesn't float in the sky, it's made of giant data centers on Earth." },
    { id = "7", text = "More than 90% of Fortune 100 companies use AWS." },
    { id = "8", text = "AWS data centers are so secure that they require retina scans and 24/7 guards." },
    { id = "9", text = "Serverless doesn't mean there are no servers, it just means you don't manage them." },
    { id = "10", text = "Each AWS Availability Zone has at least one independent power source and cooling system." },
    { id = "11", text = "Amazon once accidentally took down parts of the internet when S3 had an outage in 2017." },
    { id = "12", text = "The fastest-growing AWS service is Amazon SageMaker, used for Machine Learning." },
    { id = "13", text = "The word 'cloud' became popular in the 1990s as a metaphor for the internet." },
    { id = "14", text = "AWS Lambda can automatically scale from zero to thousands of requests per second." },
    { id = "15", text = "More data is stored in the cloud today than in all personal computers combined." }
  ]
}

resource "aws_dynamodb_table_item" "fun_facts" {
  for_each = { for fact in local.fun_facts : fact.id => fact }

  table_name = aws_dynamodb_table.cloud_facts.name
  hash_key   = aws_dynamodb_table.cloud_facts.hash_key

  item = jsonencode({
    FactID   = { S = each.value.id }
    FactText = { S = each.value.text }
  })
}

# ---------------------------------------------------------------------------
# IAM Role for Lambda
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.project_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# CloudWatch Logs permissions (scoped to this function's log group)
data "aws_iam_policy_document" "lambda_logging" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup"]
    resources = ["arn:aws:logs:${var.aws_region}:*:/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}:*"]
  }
}

resource "aws_iam_role_policy" "lambda_logging" {
  name   = "${var.project_name}-logging"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_logging.json
}

# DynamoDB read access (scoped to the CloudFacts table)
data "aws_iam_policy_document" "lambda_dynamodb" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:Scan",
      "dynamodb:Query",
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:DescribeTable"
    ]
    resources = [
      aws_dynamodb_table.cloud_facts.arn,
      "${aws_dynamodb_table.cloud_facts.arn}/index/*"
    ]
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name   = "${var.project_name}-dynamodb"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_dynamodb.json
}

# Amazon Bedrock access (call Converse API)
data "aws_iam_policy_document" "lambda_bedrock" {
  statement {
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel", "bedrock:Converse"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda_bedrock" {
  name   = "${var.project_name}-bedrock"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_bedrock.json
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.project_name}"
  retention_in_days = 14
}

# ---------------------------------------------------------------------------
# Lambda Function
# ---------------------------------------------------------------------------

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/${var.project_name}.zip"
}

resource "aws_lambda_function" "cloud_fun_facts" {
  function_name    = var.project_name
  runtime          = "python3.13"
  handler          = "lambda_function.lambda_handler"
  role             = aws_iam_role.lambda_role.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 20
  memory_size      = 128
  architectures    = ["x86_64"]

  depends_on = [
    aws_iam_role_policy.lambda_logging,
    aws_iam_role_policy.lambda_dynamodb,
    aws_iam_role_policy.lambda_bedrock,
    aws_cloudwatch_log_group.lambda_log_group,
  ]
}

# ---------------------------------------------------------------------------
# API Gateway v2 (HTTP API)
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "fun_facts_api" {
  name          = "FunfactsAPI"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.fun_facts_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.cloud_fun_facts.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_funfact" {
  api_id    = aws_apigatewayv2_api.fun_facts_api.id
  route_key = "GET /funfact"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.fun_facts_api.id
  name        = "$default"
  auto_deploy = true
}

# Permission for API Gateway to invoke Lambda
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cloud_fun_facts.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.fun_facts_api.execution_arn}/*/*/funfact"
}

# ---------------------------------------------------------------------------
# Amplify Hosting (manual deploy — no Git repository)
# ---------------------------------------------------------------------------

resource "aws_amplify_app" "fun_facts_web" {
  name     = var.project_name
  platform = "WEB"

  custom_rule {
    source = "/<*>"
    target = "/index.html"
    status = "404-200"
  }
}

resource "aws_amplify_branch" "staging" {
  app_id      = aws_amplify_app.fun_facts_web.id
  branch_name = var.amplify_branch_name
  stage       = "PRODUCTION"
}

# ---------------------------------------------------------------------------
# Outputs (useful after deploy)
# ---------------------------------------------------------------------------

output "api_gateway_url" {
  description = "API Gateway endpoint for the fun fact API"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}/funfact"
}

output "amplify_app_id" {
  description = "Amplify App ID (use for manual deploy via AWS CLI)"
  value       = aws_amplify_app.fun_facts_web.id
}

output "amplify_default_domain" {
  description = "Amplify default domain URL"
  value       = "https://${aws_amplify_app.fun_facts_web.default_domain}"
}

output "amplify_branch_name" {
  description = "Amplify branch to deploy to"
  value       = aws_amplify_branch.staging.branch_name
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.cloud_fun_facts.function_name
}

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.cloud_facts.name
}

output "iam_role_arn" {
  description = "Lambda IAM role ARN"
  value       = aws_iam_role.lambda_role.arn
}
