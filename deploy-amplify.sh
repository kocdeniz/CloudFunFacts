#!/usr/bin/env bash
set -euo pipefail

#
# deploy-amplify.sh — Deploy the website to AWS Amplify (manual, no Git required)
#
# Prerequisites:
#   - terraform apply has been run successfully
#   - AWS CLI is configured for the target account
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBSITE_DIR="${SCRIPT_DIR}/website"
ZIP_FILE="${SCRIPT_DIR}/build/amplify-deploy.zip"
REGION=$(terraform -chdir="${SCRIPT_DIR}" output -raw aws_region 2>/dev/null || echo "eu-central-1")

# ── Step 1: Get API Gateway URL from Terraform output ───────────────────────

API_URL=$(terraform -chdir="${SCRIPT_DIR}" output -raw api_gateway_url 2>/dev/null)

if [ -z "${API_URL}" ]; then
    echo "Error: Could not get API Gateway URL. Run 'terraform apply' first."
    exit 1
fi

echo "API Gateway URL: ${API_URL}"

# ── Step 2: Get Amplify app ID and branch name ─────────────────────────────

AMPLIFY_APP_ID=$(terraform -chdir="${SCRIPT_DIR}" output -raw amplify_app_id 2>/dev/null)
AMPLIFY_BRANCH=$(terraform -chdir="${SCRIPT_DIR}" output -raw amplify_branch_name 2>/dev/null)

if [ -z "${AMPLIFY_APP_ID}" ] || [ -z "${AMPLIFY_BRANCH}" ]; then
    echo "Error: Could not get Amplify app ID or branch. Run 'terraform apply' first."
    exit 1
fi

echo "Amplify App:   ${AMPLIFY_APP_ID}"
echo "Amplify Branch: ${AMPLIFY_BRANCH}"
echo "Region:         ${REGION}"

# ── Step 3: Prepare website with the API URL injected ──────────────────────

BUILD_DIR=$(mktemp -d)
cp "${WEBSITE_DIR}/index.html" "${BUILD_DIR}/index.html"

# Replace the placeholder with the actual API URL
sed -i.bak "s|{{API_GATEWAY_URL}}|${API_URL}|" "${BUILD_DIR}/index.html"
rm -f "${BUILD_DIR}/index.html.bak"

echo "Injected API URL into index.html"

# ── Step 4: Zip the website ─────────────────────────────────────────────────

mkdir -p "$(dirname "${ZIP_FILE}")"
cd "${BUILD_DIR}"
zip -r -q "${ZIP_FILE}" .
cd "${SCRIPT_DIR}"
rm -rf "${BUILD_DIR}"

echo "Created deployment zip: ${ZIP_FILE}"

# ── Step 5: Create Amplify deployment & upload ──────────────────────────────

echo "Creating Amplify deployment..."

DEPLOY_JSON=$(aws amplify create-deployment \
    --app-id "${AMPLIFY_APP_ID}" \
    --branch-name "${AMPLIFY_BRANCH}" \
    --region "${REGION}" \
    --output json)

JOB_ID=$(echo "${DEPLOY_JSON}" | python3 -c "import json,sys; print(json.load(sys.stdin)['jobId'])")
ZIP_KEY=$(echo "${DEPLOY_JSON}" | python3 -c "import json,sys; print(json.load(sys.stdin)['zipFile']['key'])")
ZIP_URL=$(echo "${DEPLOY_JSON}" | python3 -c "import json,sys; print(json.load(sys.stdin)['zipFile']['url'])")

echo "Job ID: ${JOB_ID}"

echo "Uploading website zip to Amplify S3..."
curl -sL -X PUT -o /dev/null \
    --upload-file "${ZIP_FILE}" \
    "${ZIP_URL}"

# ── Step 6: Start the deployment ────────────────────────────────────────────

echo "Starting Amplify deployment..."
aws amplify start-deployment \
    --app-id "${AMPLIFY_APP_ID}" \
    --branch-name "${AMPLIFY_BRANCH}" \
    --job-id "${JOB_ID}" \
    --region "${REGION}"

# ── Step 7: Wait for deployment to complete ─────────────────────────────────

echo "Waiting for deployment to complete..."
sleep 5

JOB_STATUS="PENDING"
ATTEMPTS=0
MAX_ATTEMPTS=30

while [ "${JOB_STATUS}" = "PENDING" ] || [ "${JOB_STATUS}" = "IN_PROGRESS" ]; do
    if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
        echo "Timeout waiting for deployment. Check the Amplify console."
        exit 1
    fi

    sleep 5
    ATTEMPTS=$((ATTEMPTS + 1))

    JOB_STATUS=$(aws amplify get-job \
        --app-id "${AMPLIFY_APP_ID}" \
        --branch-name "${AMPLIFY_BRANCH}" \
        --job-id "${JOB_ID}" \
        --region "${REGION}" \
        --query 'job.summary.status' \
        --output text 2>/dev/null || echo "PENDING")

    echo "  Status: ${JOB_STATUS} (attempt ${ATTEMPTS}/${MAX_ATTEMPTS})"
done

if [ "${JOB_STATUS}" = "SUCCEED" ]; then
    echo ""
    echo "========================================="
    echo "  ✅ Amplify deployment succeeded!"
    echo "========================================="
    echo ""

    AMPLIFY_DOMAIN=$(terraform -chdir="${SCRIPT_DIR}" output -raw amplify_default_domain 2>/dev/null)
    echo "Website URL: ${AMPLIFY_DOMAIN}"
    echo "API URL:     ${API_URL}"
else
    echo ""
    echo "❌ Deployment failed with status: ${JOB_STATUS}"
    echo "Check the Amplify console for details."
    exit 1
fi
