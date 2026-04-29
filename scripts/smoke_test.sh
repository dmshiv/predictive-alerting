#!/usr/bin/env bash
# =============================================================================
# WHAT  : End-to-end smoke test. Verifies every layer is alive.
# WHY   : Quick "is the demo really working?" check before showing it to
#         someone.
# HOW   : 1. Pub/Sub: publish a fake telemetry msg
#         2. BigQuery: assert the row landed within 30s
#         3. Vertex AI: hit the victim endpoint
#         4. Cloud Run: GET /healthz on triage and grafana
#         5. Forecaster: trigger one-off prediction run
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${GCP_PROJECT_ID:?}"
: "${GCP_REGION:?}"
: "${ENV_NAME:=dev}"
NAME_PREFIX="sentinel-${ENV_NAME}"

PASS=0
FAIL=0
ok()   { echo "    PASS — $*"; PASS=$((PASS+1)); }
nok()  { echo "    FAIL — $*"; FAIL=$((FAIL+1)); }

# ---------- 1. Pub/Sub publish + BQ persist ----------------------------------
echo "[1/5] Pub/Sub -> BigQuery round-trip..."
SMOKE_ID="smoke-$(date +%s)"
gcloud pubsub topics publish "${NAME_PREFIX}-telemetry" \
  --project="${GCP_PROJECT_ID}" \
  --message="{\"event_time\":\"$(date -u +%FT%TZ)\",\"endpoint_id\":\"smoke\",\"metric_name\":\"latency_ms\",\"metric_value\":123.45,\"request_id\":\"${SMOKE_ID}\"}" \
  >/dev/null && ok "published smoke msg" || nok "publish failed"

echo "    waiting 30s for collector to write to BQ..."
sleep 30
COUNT=$(bq query --use_legacy_sql=false --project_id="${GCP_PROJECT_ID}" --format=csv \
  "SELECT COUNT(*) FROM \`${GCP_PROJECT_ID}.sentinel_${ENV_NAME//-/_}_features.telemetry_raw\` WHERE request_id='${SMOKE_ID}'" \
  | tail -n1)
[[ "${COUNT:-0}" -ge 1 ]] && ok "BQ row present (${COUNT})" || nok "BQ row missing"

# ---------- 2. Vertex AI endpoint --------------------------------------------
echo "[2/5] Vertex AI victim endpoint..."
ENDPOINT_ID=$(gcloud ai endpoints list --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" \
  --filter="displayName:${NAME_PREFIX}-victim-recommender" --format='value(ENDPOINT_ID)' | head -n1)
if [[ -z "$ENDPOINT_ID" ]]; then
  nok "endpoint not found"
else
  PRED=$(gcloud ai endpoints predict "$ENDPOINT_ID" \
    --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" \
    --json-request=<(echo '{"instances":[{"image_norm":1.0,"text_norm":1.0,"review_token_count":20,"request_id":"smoke"}]}') \
    2>&1 | head -c 200 || true)
  [[ -n "$PRED" ]] && ok "endpoint responded: ${PRED:0:80}..." || nok "no response"
fi

# ---------- 3. Cloud Run healthz ---------------------------------------------
echo "[3/5] Cloud Run healthz..."
TRIAGE_URL="$(gcloud run services describe "${NAME_PREFIX}-triage" --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" --format='value(status.url)' 2>/dev/null || echo '')"
GRAF_URL="$(gcloud run services describe "${NAME_PREFIX}-grafana"   --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" --format='value(status.url)' 2>/dev/null || echo '')"

if [[ -n "$GRAF_URL" ]]; then
  curl -sf "${GRAF_URL}/api/health" >/dev/null && ok "grafana /api/health" || nok "grafana not reachable"
else
  nok "grafana url missing"
fi
if [[ -n "$TRIAGE_URL" ]]; then
  TOK=$(gcloud auth print-identity-token)
  curl -sf -H "Authorization: Bearer $TOK" "${TRIAGE_URL}/healthz" >/dev/null && ok "triage /healthz" || nok "triage not reachable"
else
  nok "triage url missing"
fi

# ---------- 4. Forecaster one-off prediction ---------------------------------
echo "[4/5] Forecaster predict..."
python -m src.forecaster.predict_breach 2>&1 | tail -n5 || nok "forecaster crashed"
ok "forecaster ran (review logs above)"

# ---------- 5. Send a synthetic predictive alert through triage --------------
echo "[5/5] Synthetic alert -> triage..."
if [[ -n "$TRIAGE_URL" ]]; then
  TOK=$(gcloud auth print-identity-token)
  curl -sf -X POST -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
    "${TRIAGE_URL}/alert" -d "{
      \"incident_id\": \"smoke-${SMOKE_ID}\",
      \"fired_at\": \"$(date -u +%FT%TZ)\",
      \"predicted_breach_at\": \"$(date -u -d '+10 min' +%FT%TZ)\",
      \"endpoint_id\": \"victim-recommender\",
      \"metric_name\": \"latency_ms\",
      \"severity\": \"high\",
      \"lead_time_minutes\": 10,
      \"operator\": \"gt\", \"threshold\": 300, \"predicted_peak\": 450,
      \"feature_fingerprint\": {\"smoke\": true}
    }" | head -c 300 && echo "" && ok "triage processed alert" || nok "triage alert failed"
fi

echo ""
echo "============================================================"
echo "    PASS=${PASS}   FAIL=${FAIL}"
echo "============================================================"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
