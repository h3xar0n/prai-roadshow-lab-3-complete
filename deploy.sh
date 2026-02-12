#!/bin/bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "${SCRIPT_DIR}"

if [ -f ".env" ]; then
  source .env
fi

# Add local terraform binary to path
if [ -d "${SCRIPT_DIR}/terraform_bin" ]; then
  export PATH="${SCRIPT_DIR}/terraform_bin:${PATH}"
fi

if [[ "${GOOGLE_CLOUD_PROJECT}" == "" ]]; then
  GOOGLE_CLOUD_PROJECT=$(gcloud config get-value project -q)
fi
if [[ "${GOOGLE_CLOUD_PROJECT}" == "" ]]; then
  echo "ERROR: Run 'gcloud config set project' command to set active project, or set GOOGLE_CLOUD_PROJECT environment variable."
  exit 1
fi

REGION="${GOOGLE_CLOUD_LOCATION}"
if [[ "${REGION}" == "global" ]]; then
  echo "GOOGLE_CLOUD_LOCATION is set to 'global'. Getting a default location for Cloud Run."
  REGION=""
fi

if [[ "${REGION}" == "" ]]; then
  REGION=$(gcloud config get-value compute/region -q)
  if [[ "${REGION}" == "" ]]; then
    REGION="us-central1"
    echo "WARNING: Cannot get a configured compute region. Defaulting to ${REGION}."
  fi
fi
echo "Using project ${GOOGLE_CLOUD_PROJECT}."
echo "Using compute region ${REGION}."

# Terraform Deployment
echo "Initializing Terraform..."
if command -v terraform &> /dev/null; then
    terraform -chdir=terraform init

    echo "Importing existing resources if needed..."
    bash terraform/import.sh "${GOOGLE_CLOUD_PROJECT}" "${REGION}"

    echo "Applying Terraform configuration..."
    terraform -chdir=terraform apply -auto-approve \
      -var="project=${GOOGLE_CLOUD_PROJECT}" \
      -var="region=${REGION}" \
      -var="billing_project=${GOOGLE_CLOUD_PROJECT}"

    echo "Exporting Terraform output to .env..."
    TEMPLATE_NAME=$(terraform -chdir=terraform output -raw model_armor_template_name)
    touch .env
    if grep -q "TEMPLATE_NAME=" .env; then
      sed -i "s|TEMPLATE_NAME=.*|TEMPLATE_NAME=${TEMPLATE_NAME}|" .env
    else
      echo "TEMPLATE_NAME=${TEMPLATE_NAME}" >> .env
    fi
else
    echo "WARNING: terraform not found in PATH. Skipping Terraform deployment steps."
    # Fallback: check if TEMPLATE_NAME is already in .env
    if [[ -z "${TEMPLATE_NAME}" ]]; then
        TEMPLATE_NAME=$(grep TEMPLATE_NAME .env | cut -d '=' -f2)
    fi
fi

if [[ "${TEMPLATE_NAME}" == "" ]]; then
  echo "ERROR: TEMPLATE_NAME not found. Please ensure Terraform has run or set it in .env manually."
  exit 1
fi


if [[ "${SERVICE_SUFFIX}" == "" ]]; then
  SERVICE_SUFFIX="-prod-ready-3"
fi
echo "Using service suffix: '${SERVICE_SUFFIX}'"

# Function to deploy from source with root context
# Copies Dockerfile to root, deploys, then cleans up
deploy_service() {
    local SERVICE_NAME=$1
    local DOCKERFILE_PATH=$2
    shift 2
    local ARGS=("$@")

    echo "Deploying ${SERVICE_NAME}..."
    cp "${DOCKERFILE_PATH}" Dockerfile
    # Trap to ensure Dockerfile is removed
    trap "rm -f Dockerfile" EXIT

    gcloud run deploy "${SERVICE_NAME}" \
      --source . \
      "${ARGS[@]}"

    rm -f Dockerfile
    trap - EXIT
}

# Deploy Researcher
deploy_service "researcher${SERVICE_SUFFIX}" "agents/researcher/Dockerfile" \
  --project $GOOGLE_CLOUD_PROJECT \
  --region $REGION \
  --labels dev-tutorial=prod-ready-3 \
  --no-allow-unauthenticated \
  --set-env-vars GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT}" \
  --set-env-vars GOOGLE_GENAI_USE_VERTEXAI="true"

RESEARCHER_URL=$(gcloud run services describe "researcher${SERVICE_SUFFIX}" --region $REGION --format='value(status.url)')

# Deploy Content Builder
deploy_service "content-builder${SERVICE_SUFFIX}" "agents/content_builder/Dockerfile" \
  --project $GOOGLE_CLOUD_PROJECT \
  --region $REGION \
  --labels dev-tutorial=prod-ready-3 \
  --no-allow-unauthenticated \
  --set-env-vars GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT}" \
  --set-env-vars GOOGLE_GENAI_USE_VERTEXAI="true"

CONTENT_BUILDER_URL=$(gcloud run services describe "content-builder${SERVICE_SUFFIX}" --region $REGION --format='value(status.url)')

# Deploy Judge
deploy_service "judge${SERVICE_SUFFIX}" "agents/judge/Dockerfile" \
  --project $GOOGLE_CLOUD_PROJECT \
  --region $REGION \
  --labels dev-tutorial=prod-ready-3 \
  --no-allow-unauthenticated \
  --set-env-vars GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT}" \
  --set-env-vars GOOGLE_GENAI_USE_VERTEXAI="true"

JUDGE_URL=$(gcloud run services describe "judge${SERVICE_SUFFIX}" --region $REGION --format='value(status.url)')

# Deploy Orchestrator
deploy_service "orchestrator${SERVICE_SUFFIX}" "agents/orchestrator/Dockerfile" \
  --project $GOOGLE_CLOUD_PROJECT \
  --region $REGION \
  --labels dev-tutorial=prod-ready-3 \
  --no-allow-unauthenticated \
  --set-env-vars RESEARCHER_AGENT_CARD_URL=$RESEARCHER_URL/a2a/agent/.well-known/agent-card.json \
  --set-env-vars JUDGE_AGENT_CARD_URL=$JUDGE_URL/a2a/agent/.well-known/agent-card.json \
  --set-env-vars CONTENT_BUILDER_AGENT_CARD_URL=$CONTENT_BUILDER_URL/a2a/agent/.well-known/agent-card.json \
  --set-env-vars GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT}" \
  --set-env-vars GOOGLE_GENAI_USE_VERTEXAI="true"

ORCHESTRATOR_URL=$(gcloud run services describe "orchestrator${SERVICE_SUFFIX}" --region $REGION --format='value(status.url)')

# Deploy Course Creator (Frontend)
deploy_service "course-creator${SERVICE_SUFFIX}" "app/Dockerfile" \
  --project $GOOGLE_CLOUD_PROJECT \
  --region $REGION \
  --labels dev-tutorial=prod-ready-3 \
  --allow-unauthenticated \
  --set-env-vars AGENT_SERVER_URL=$ORCHESTRATOR_URL \
  --set-env-vars GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT}" \
  --set-env-vars TEMPLATE_NAME="${TEMPLATE_NAME}"

echo "Deployment complete!"
