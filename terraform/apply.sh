#!/bin/bash
set -e

# Determine script directory
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "${SCRIPT_DIR}"

# Check for .env in parent directory
if [ -f "../.env" ]; then
  source "../.env"
fi

# Add local terraform binary to path if it exists in parent directory
if [ -d "../terraform_bin" ]; then
  export PATH="$(pwd)/../terraform_bin:${PATH}"
fi

# Set Project ID
if [[ "${GOOGLE_CLOUD_PROJECT}" == "" ]]; then
  GOOGLE_CLOUD_PROJECT=$(gcloud config get-value project -q)
fi
if [[ "${GOOGLE_CLOUD_PROJECT}" == "" ]]; then
  echo "ERROR: Run 'gcloud config set project' command to set active project, or set GOOGLE_CLOUD_PROJECT environment variable."
  exit 1
fi

# Set Region
REGION="${GOOGLE_CLOUD_LOCATION}"
if [[ "${REGION}" == "global" ]]; then
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

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Run import script if it exists
if [ -f "import.sh" ]; then
    echo "Importing existing resources if needed..."
    bash import.sh "${GOOGLE_CLOUD_PROJECT}" "${REGION}"
fi

# Apply Terraform
echo "Applying Terraform configuration..."
terraform apply -auto-approve \
  -var="project=${GOOGLE_CLOUD_PROJECT}" \
  -var="region=${REGION}" \
  -var="billing_project=${GOOGLE_CLOUD_PROJECT}"

# Output TEMPLATE_NAME
TEMPLATE_NAME=$(terraform output -raw model_armor_template_name)
echo "---------------------------------------------------"
echo "Terraform applied successfully."
echo "TEMPLATE_NAME=${TEMPLATE_NAME}"
echo "---------------------------------------------------"

# Update .env in parent directory if it exists or create it
if [ -f "../.env" ]; then
    echo "Updating ../.env with TEMPLATE_NAME..."
    if grep -q "TEMPLATE_NAME=" ../.env; then
      sed -i "s|TEMPLATE_NAME=.*|TEMPLATE_NAME=${TEMPLATE_NAME}|" ../.env
    else
      echo "TEMPLATE_NAME=${TEMPLATE_NAME}" >> ../.env
    fi
else
    echo "Creating ../.env with TEMPLATE_NAME..."
    echo "TEMPLATE_NAME=${TEMPLATE_NAME}" > ../.env
fi
