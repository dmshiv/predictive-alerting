#!/usr/bin/env bash
# =============================================================================
# WHAT  : Sets the alert-email destination — both as a Secret Manager value
#         (read by the triage service) and as the Cloud Monitoring
#         notification channel (created by 17-monitoring on apply).
# WHY   : Email is the always-works alert path.
# HOW   : `./scripts/setup_email.sh you@company.com`
#         Then re-run `./scripts/start.sh` so 17-monitoring picks up the value.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

set -a
# shellcheck disable=SC1091
source .env
set +a

EMAIL="${1:-}"
if [[ -z "$EMAIL" ]]; then
  echo "Usage: $0 <email_address>"
  exit 1
fi

: "${GCP_PROJECT_ID:?}"
: "${ENV_NAME:=dev}"

# 1. Persist in .env so subsequent terraform applies pick it up
if grep -q '^ALERT_EMAIL=' .env 2>/dev/null; then
  sed -i "s|^ALERT_EMAIL=.*|ALERT_EMAIL=${EMAIL}|" .env
else
  echo "ALERT_EMAIL=${EMAIL}" >> .env
fi
echo ">>> .env updated with ALERT_EMAIL=${EMAIL}"

# 2. Push to Secret Manager (used by triage for in-message references)
SECRET="sentinel-${ENV_NAME}-alert-email-target"
echo -n "${EMAIL}" | gcloud secrets versions add "${SECRET}" \
  --project="${GCP_PROJECT_ID}" --data-file=-

# 3. Re-apply 17-monitoring so the notification channel + alert policies
#    pick up the new email
echo ">>> re-applying 17-monitoring with the new email..."
pushd terraform/17-monitoring >/dev/null
terraform apply -auto-approve \
  -var "project_id=${GCP_PROJECT_ID}" \
  -var "region=${GCP_REGION}" \
  -var "zone=${GCP_ZONE:-${GCP_REGION}-a}" \
  -var "env_name=${ENV_NAME}" \
  -var "tfstate_bucket=${TFSTATE_BUCKET}" \
  -var "alert_email=${EMAIL}"
popd >/dev/null

echo ">>> alert email setup complete."
