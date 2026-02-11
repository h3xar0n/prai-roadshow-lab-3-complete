#!/bin/bash
set -e

# This script attempts to import existing resources into Terraform state.
# It is designed to be idempotent and safe to run multiple times.

PROJECT="$1"
REGION="$2"

if [[ -z "$PROJECT" || -z "$REGION" ]]; then
  echo "Usage: $0 <PROJECT> <REGION>"
  exit 1
fi

# Switch to the script's directory so terraform commands work
cd "$(dirname "$0")"

echo "Checking for existing resources to import..."

# Function to attempt import
try_import() {
  local RESOURCE="$1"
  local ID="$2"

  echo "Attempting to import $RESOURCE ($ID)..."
  
  # Check if resource is already in state
  if terraform state list | grep -q "^${RESOURCE}$"; then
    echo "  -> Resource $RESOURCE is already managed by Terraform."
    return 0
  fi

  # Attempt import
  # capturing stderr to check for "resource already managed" or "does not exist" errors if needed
  # usually terraform import errors out if it doesn't exist, which is what we want (so we know to create it)
  # but we want to SUPPRESS the error if it's just "doesn't exist" so the script doesn't fail
  if terraform import -var="project=${PROJECT}" -var="region=${REGION}" -var="billing_project=${PROJECT}" "$RESOURCE" "$ID"; then
    echo "  -> Successfully imported $RESOURCE."
  else
    echo "  -> Import failed (likely because resource does not exist). Terraform will act to create it."
    # We don't exit here, we let the script verify via `terraform plan` or just let `terraform apply` handle creation.
    # Actually, `terraform import` failing is expected if the resource doesn't exist.
    # We just clear the failure.
    return 0
  fi
}

# Import DLP Inspect Template
try_import "google_data_loss_prevention_inspect_template.sensitive_data_inspector" "projects/${PROJECT}/locations/${REGION}/inspectTemplates/sensitive-data-inspector"

# Import DLP Deidentify Template
try_import "google_data_loss_prevention_deidentify_template.sensitive_data_redactor" "projects/${PROJECT}/locations/${REGION}/deidentifyTemplates/sensitive-data-redactor"

# Import Model Armor Template
try_import "google_model_armor_template.course_creator_security_policy" "projects/${PROJECT}/locations/${REGION}/templates/course-creator-security-policy"

# Import Artifact Registry Repository
try_import "google_artifact_registry_repository.cloud_run_source_deploy" "projects/${PROJECT}/locations/${REGION}/repositories/cloud-run-source-deploy"

echo "Import check complete."
