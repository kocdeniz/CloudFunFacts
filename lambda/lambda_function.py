import boto3
import random
import json

# DynamoDB connection
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("CloudFacts")

# Bedrock client
bedrock = boto3.client("bedrock-runtime")

def lambda_handler(event, context):
    # Fetch all facts from DynamoDB
    response = table.scan()
    items = response.get("Items", [])
    if not items:
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type"
            },
            "body": json.dumps({"fact": "No facts available in DynamoDB."})
        }

    fact = random.choice(items)["FactText"]

    # Messages payload for Bedrock Converse API
    messages = [
        {
            "role": "user",
            "content": [
                {
                    "text": f"Take this cloud computing fact and make it fun and engaging in 1-2 sentences maximum. Keep it short and witty: {fact}"
                }
            ]
        }
    ]

    try:
        # Call MiniMax M2.1 on Bedrock using the Converse API
        response = bedrock.converse(
            modelId="minimax.minimax-m2.1",
            messages=messages,
            inferenceConfig={
                "maxTokens": 100,
                "temperature": 0.7
            }
        )

        # Extract output text from Converse response
        witty_fact = response["output"]["message"]["content"][0]["text"].strip()

        # Fallback if response is empty or too long
        if not witty_fact or len(witty_fact) > 300:
            witty_fact = fact

    except Exception as e:
        print(f"Bedrock error: {e}")
        witty_fact = fact

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type"
        },
        "body": json.dumps({"fact": witty_fact})
    }
