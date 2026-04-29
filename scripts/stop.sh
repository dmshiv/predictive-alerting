#!/usr/bin/env bash

##temporay stop the services where the project stays intact 

# =============================================================================
# WHAT  : Cost-saver. Stops/scales-down the expensive resources but keeps
#         data + IAM + buckets so we can resume cheaply.
# WHY   : GKE Autopilot, the loadgen VM, and Cloud Run min-instance are the
#         meaningful cost drivers. Killing them overnight saves ~$5-8/day.
# HOW   : Scale GKE deployments to 0; stop the VM; set Cloud Run min=0.
# WHEN  : Run before going to bed.
# RESTORE: ./scripts/start.sh runs idempotently and brings everything back.
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

echo ">>> stopping cost-driving resources..."

# 1. Stop the load-gen VM
echo "    [1/4] stopping loadgen VM..."
gcloud compute instances stop "${NAME_PREFIX}-loadgen" \
  --zone="${GCP_ZONE:-${GCP_REGION}-a}" \
  --project="${GCP_PROJECT_ID}" --quiet || true

# 2. Stop the Workbench instance
echo "    [2/4] stopping workbench..."
gcloud workbench instances stop "${NAME_PREFIX}-workbench" \
  --location="${GCP_ZONE:-${GCP_REGION}-a}" \
  --project="${GCP_PROJECT_ID}" --quiet || true

# 3. Scale GKE detector + collector to 0 replicas
echo "    [3/4] scaling GKE deployments to 0..."
gcloud container clusters get-credentials "${NAME_PREFIX}-gke" \
  --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" >/dev/null 2>&1 || true
kubectl scale -n sentinel deploy --all --replicas=0 || true

# 4. Set Cloud Run min instances to 0 (Grafana stays cold)
echo "    [4/4] cooling Cloud Run services..."
gcloud run services update "${NAME_PREFIX}-grafana" \
  --min-instances=0 --region="${GCP_REGION}" \
  --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null || true

echo ""
echo ">>> stop complete. Run ./scripts/start.sh to resume."
echo "    To FULLY destroy (delete buckets, BQ, etc), run:"
echo "    for d in \$(ls -r terraform); do (cd terraform/\$d && terraform destroy -auto-approve); done"
