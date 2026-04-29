#!/usr/bin/env bash
# =============================================================================
# WHAT: Local convenience — submit Cloud Build for all 5 Dockerfiles.
# WHY:  One command, called by start.sh.
# =============================================================================
set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:?set GCP_PROJECT_ID}"
REGION="${GCP_REGION:-us-central1}"
REPO="sentinel-images"

cd "$(dirname "$0")/.."
echo ">>> Submitting Cloud Build (all 5 images)..."
gcloud builds submit \
  --project="$PROJECT_ID" \
  --config=docker/cloudbuild.yaml \
  --substitutions=_REGION="$REGION",_REPO="$REPO" \
  .
