#!/usr/bin/env bash
# =============================================================================
# WHAT  : Writes a Slack incoming-webhook URL into Secret Manager so the
#         triage Cloud Run service can post alerts.
# WHY   : We don't want the webhook in git. Secret Manager is the right home.
# HOW   : `./scripts/setup_slack.sh https://hooks.slack.com/services/T0/B0/abc`
# OPT   : Optional. Without this, alerts still fire to email + Cloud Logging.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

set -a
# shellcheck disable=SC1091
source .env
set +a

WEBHOOK="${1:-}"
if [[ -z "$WEBHOOK" ]]; then
  echo "Usage: $0 <slack_webhook_url>"
  echo "  Get one at: https://api.slack.com/messaging/webhooks"
  exit 1
fi

: "${GCP_PROJECT_ID:?}"
: "${ENV_NAME:=dev}"
SECRET="sentinel-${ENV_NAME}-slack-webhook"

echo ">>> writing webhook to Secret Manager: ${SECRET}"
echo -n "${WEBHOOK}" | gcloud secrets versions add "${SECRET}" \
  --project="${GCP_PROJECT_ID}" \
  --data-file=-

echo ">>> testing the webhook..."
curl -sS -X POST -H 'Content-Type: application/json' \
  --data '{"text":":white_check_mark: Sentinel-Forecast Slack channel configured."}' \
  "${WEBHOOK}" && echo "" && echo ">>> Slack channel ready."
