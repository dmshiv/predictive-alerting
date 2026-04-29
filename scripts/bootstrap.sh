#!/usr/bin/env bash
# =============================================================================
# WHAT  : One-time bootstrap. Creates the GCS bucket Terraform uses for state,
#         enables billing on the project, and writes .env from .env.example.
# WHY   : Run this ONCE per fresh GCP project, before `start.sh`. Terraform
#         needs a remote state bucket to exist before it can `init`.
# WHEN  : First-time setup only.
# HOW   : `./scripts/bootstrap.sh`  (after editing .env.example -> .env)
# LAYMAN: Lays down the foundation (project, billing, state bucket) so the
#         rest of the build can stack on top.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 1. Source .env (or fail loudly)
if [[ ! -f .env ]]; then
  if [[ -f .env.example ]]; then
    echo ">>> .env not found — copy .env.example to .env and edit it first."
    echo ">>>   cp .env.example .env"
    echo ">>>   $EDITOR .env"
    exit 1
  else
    echo "ERROR: .env.example missing too; corrupted checkout?"
    exit 1
  fi
fi
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${GCP_PROJECT_ID:?set GCP_PROJECT_ID in .env}"
: "${GCP_REGION:?set GCP_REGION in .env}"
: "${ENV_NAME:=dev}"

STATE_BUCKET="${GCP_PROJECT_ID}-sentinel-${ENV_NAME}-tfstate"

echo ">>> bootstrap for project: $GCP_PROJECT_ID, region: $GCP_REGION, env: $ENV_NAME"

# 2. Make sure gcloud is pointed at the right project
gcloud config set project "$GCP_PROJECT_ID" --quiet

# 3. Verify billing
billing_account="$(gcloud beta billing projects describe "$GCP_PROJECT_ID" --format='value(billingAccountName)' 2>/dev/null || true)"
if [[ -z "$billing_account" ]]; then
  echo ">>> WARNING: project has no billing account linked. Vertex AI/GKE will fail."
  echo ">>> Link one in: https://console.cloud.google.com/billing/linkedaccount?project=${GCP_PROJECT_ID}"
fi

# 4. Enable the bare-minimum APIs required to *create* the state bucket and
#    later run terraform. (00-globals enables the rest.)
echo ">>> enabling minimal APIs..."
gcloud services enable \
  storage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  iam.googleapis.com \
  --quiet

# 5. Create the state bucket (idempotent)
if gsutil ls -b "gs://${STATE_BUCKET}" >/dev/null 2>&1; then
  echo ">>> state bucket gs://${STATE_BUCKET} already exists"
else
  echo ">>> creating state bucket: gs://${STATE_BUCKET}"
  gsutil mb -p "$GCP_PROJECT_ID" -l "$GCP_REGION" -b on "gs://${STATE_BUCKET}"
  gsutil versioning set on "gs://${STATE_BUCKET}"
fi

# 6. Persist for terraform to find
echo "TFSTATE_BUCKET=${STATE_BUCKET}" >> .env
sort -u .env -o .env

echo ""
echo ">>> bootstrap complete."
echo "    State bucket: gs://${STATE_BUCKET}"
echo "    Next step:   ./scripts/start.sh"
