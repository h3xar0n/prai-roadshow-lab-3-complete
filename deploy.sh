#!/bin/bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "${SCRIPT_DIR}"

if [ -f ".env" ]; then
  source .env
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

if [[ "${TEMPLATE_NAME}" == "" ]]; then
  echo "ERROR: Failed to get TEMPLATE_NAME from Terraform output."
  exit 1
fi


if [[ "${SERVICE_SUFFIX}" == "" ]]; then
  SERVICE_SUFFIX=""
fi
echo "Using service suffix: '${SERVICE_SUFFIX}'"

# Helper function to build image with correct context
build_image() {
  local DOCKERFILE=$1
  local IMAGE_TAG=$2
  
  echo "Building ${IMAGE_TAG} from ${DOCKERFILE}..."
  cp "${DOCKERFILE}" Dockerfile
  # Use trap to ensure Dockerfile is removed even if build fails
  trap "rm -f Dockerfile" EXIT
  
  gcloud builds submit --tag "${IMAGE_TAG}" .
  
  rm -f Dockerfile
  trap - EXIT
}

echo "Deploying researcher..."
RESEARCHER_IMAGE="us-central1-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/cloud-run-source-deploy/researcher${SERVICE_SUFFIX}:latest"
build_image "agents/researcher/Dockerfile" "${RESEARCHER_IMAGE}"

gcloud run deploy "researcher${SERVICE_SUFFIX}" \
  --image "${RESEARCHER_IMAGE}" \
  --project $GOOGLE_CLOUD_PROJECT \
  --region $REGION \
  --labels dev-tutorial=prod-ready-3 \
  --no-allow-unauthenticated \
  --set-env-vars GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT}" \
  --set-env-vars GOOGLE_GENAI_USE_VERTEXAI="true"
RESEARCHER_URL=$(gcloud run services describe "researcher${SERVICE_SUFFIX}" --region $REGION --format='value(status.url)')

echo "Deploying content-builder..."
CONTENT_BUILDER_IMAGE="us-central1-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/cloud-run-source-deploy/content-builder${SERVICE_SUFFIX}:latest"
build_image "agents/content_builder/Dockerfile" "${CONTENT_BUILDER_IMAGE}"

gcloud run deploy "content-builder${SERVICE_SUFFIX}" \
  --image "${CONTENT_BUILDER_IMAGE}" \
  --project $GOOGLE_CLOUD_PROJECT \
  --region $REGION \
  --labels dev-tutorial=prod-ready-3 \
  --no-allow-unauthenticated \
  --set-env-vars GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT}" \
  --set-env-vars GOOGLE_GENAI_USE_VERTEXAI="true"
CONTENT_BUILDER_URL=$(gcloud run services describe "content-builder${SERVICE_SUFFIX}" --region $REGION --format='value(status.url)')

echo "Deploying judge..."
JUDGE_IMAGE="us-central1-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/cloud-run-source-deploy/judge${SERVICE_SUFFIX}:latest"
build_image "agents/judge/Dockerfile" "${JUDGE_IMAGE}"

gcloud run deploy "judge${SERVICE_SUFFIX}" \
  --image "${JUDGE_IMAGE}" \
  --project $GOOGLE_CLOUD_PROJECT \
  --region $REGION \
  --labels dev-tutorial=prod-ready-3 \
  --no-allow-unauthenticated \
  --set-env-vars GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT}" \
  --set-env-vars GOOGLE_GENAI_USE_VERTEXAI="true"
JUDGE_URL=$(gcloud run services describe "judge${SERVICE_SUFFIX}" --region $REGION --format='value(status.url)')

echo "Deploying orchestrator..."
ORCHESTRATOR_IMAGE="us-central1-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/cloud-run-source-deploy/orchestrator${SERVICE_SUFFIX}:latest"
build_image "agents/orchestrator/Dockerfile" "${ORCHESTRATOR_IMAGE}"

gcloud run deploy "orchestrator${SERVICE_SUFFIX}" \
  --image "${ORCHESTRATOR_IMAGE}" \
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

echo "Deploying course-creator (frontend)..."
COURSE_CREATOR_IMAGE="us-central1-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/cloud-run-source-deploy/course-creator${SERVICE_SUFFIX}:latest"
build_image "app/Dockerfile" "${COURSE_CREATOR_IMAGE}"

gcloud run deploy "course-creator${SERVICE_SUFFIX}" \
  --image "${COURSE_CREATOR_IMAGE}" \
  --project $GOOGLE_CLOUD_PROJECT \
  --region $REGION \
  --labels dev-tutorial=prod-ready-3 \
  --allow-unauthenticated \
  --set-env-vars AGENT_SERVER_URL=$ORCHESTRATOR_URL \
  --set-env-vars GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT}" \
  --set-env-vars TEMPLATE_NAME="${TEMPLATE_NAME}"
