#!/usr/bin/env bash

##destroyes all our TF cloud infra ******
# =============================================================================
# WHAT  : FULL teardown. Destroys every Terraform-managed resource in the
#         REVERSE order they were created, with the same lock + retry
#         protection as start.sh.
# WHY   : `stop.sh` only pauses (saves money). When you are TRULY done with
#         the project, run this to nuke everything to $0.
# HOW   : Iterates terraform/<NN>-*/ from 18 -> 00, calling `terraform destroy`
#         on each with -lock-timeout and a retry loop.
# WARN  : This deletes data (BigQuery rows, GCS objects, model artefacts).
#         You will be prompted "type yes" before anything is destroyed.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ---------- env --------------------------------------------------------------
if [[ ! -f .env ]]; then
  echo "ERROR: .env missing." >&2
  exit 1
fi
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${GCP_PROJECT_ID:?}"
: "${GCP_REGION:?}"
: "${ENV_NAME:=dev}"
: "${TFSTATE_BUCKET:?ran bootstrap.sh?}"

NAME_PREFIX="sentinel-${ENV_NAME}"

# ---------- safety -----------------------------------------------------------
echo ""
echo "============================================================"
echo "    !!  IRREVERSIBLE FULL TEARDOWN  !!"
echo "============================================================"
echo "    Project       : ${GCP_PROJECT_ID}"
echo "    Region        : ${GCP_REGION}"
echo "    Env           : ${ENV_NAME}"
echo "    State bucket  : gs://${TFSTATE_BUCKET}"
echo ""
echo "    This will DELETE:"
echo "      - GKE cluster + all data on it"
echo "      - Vertex AI endpoints, models, pipelines, workbench, tensorboard"
echo "      - BigQuery datasets + every row in them"
echo "      - GCS buckets (raw, processed, models, code, tb-logs)"
echo "      - Pub/Sub topics + subscriptions"
echo "      - Cloud Run services, scheduler jobs, monitoring dashboards"
echo "      - VPC, IAM, secrets"
echo ""
read -r -p "    Type 'yes-destroy-everything' to proceed: " confirm
if [[ "$confirm" != "yes-destroy-everything" ]]; then
  echo "    aborted."
  exit 1
fi

# ---------- helpers ----------------------------------------------------------
TF_VARS=(
  -var "project_id=${GCP_PROJECT_ID}"
  -var "region=${GCP_REGION}"
  -var "zone=${GCP_ZONE:-${GCP_REGION}-a}"
  -var "env_name=${ENV_NAME}"
  -var "tfstate_bucket=${TFSTATE_BUCKET}"
)

TF_LOCK_TIMEOUT="300s"
TF_RETRY_MAX="${TF_RETRY_MAX:-3}"

destroy_folder() {
  local folder="$1"
  local attempt=1

  echo ""
  echo "============================================================"
  echo ">>> Destroying ${folder}    (lock-timeout=${TF_LOCK_TIMEOUT})"
  echo "============================================================"

  # Skip if there's no state file (folder was never applied)
  if ! gsutil ls "gs://${TFSTATE_BUCKET}/${folder}/state/default.tfstate" >/dev/null 2>&1; then
    echo "    [skip] no state for ${folder}, nothing to destroy"
    return 0
  fi

  pushd "terraform/${folder}" >/dev/null

  local extra_vars=()
  if [[ "$folder" == "17-monitoring" && -n "${ALERT_EMAIL:-}" ]]; then
    extra_vars+=(-var "alert_email=${ALERT_EMAIL}")
  fi
  # 02-iam was applied with WI bindings enabled in start.sh; pass the same here
  if [[ "$folder" == "02-iam" ]]; then
    extra_vars+=(-var "enable_workload_identity_bindings=true")
  fi

  terraform init -reconfigure \
    -backend-config="bucket=${TFSTATE_BUCKET}" \
    -backend-config="prefix=${folder}/state" \
    -lock-timeout="${TF_LOCK_TIMEOUT}" >/dev/null

  while (( attempt <= TF_RETRY_MAX )); do
    if terraform destroy -auto-approve \
        -lock-timeout="${TF_LOCK_TIMEOUT}" \
        "${TF_VARS[@]}" "${extra_vars[@]}"; then
      break
    fi
    if (( attempt == TF_RETRY_MAX )); then
      echo "    [destroy] FAILED on ${folder}; continuing with the rest" >&2
      popd >/dev/null
      return 1
    fi
    local backoff=$(( attempt * 30 ))
    echo "    [destroy] attempt ${attempt}/${TF_RETRY_MAX} failed; sleeping ${backoff}s..."
    sleep "$backoff"
    ((attempt++))
  done

  popd >/dev/null
}

# ---------- 1. Pre-destroy cleanup -------------------------------------------
# Some resources need manual help before terraform can delete them:
#   - Vertex AI endpoints with deployed models (must undeploy first)
#   - GKE workloads (kill any LoadBalancer services holding LBs)
echo ""
echo ">>> Pre-destroy cleanup..."

# 1a. Undeploy all Vertex AI models
for ep_id in $(gcloud ai endpoints list --region="${GCP_REGION}" \
                --project="${GCP_PROJECT_ID}" --format='value(ENDPOINT_ID)' 2>/dev/null); do
  for dep_id in $(gcloud ai endpoints describe "$ep_id" \
                    --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" \
                    --format='value(deployedModels.id)' 2>/dev/null); do
    echo "    undeploying model $dep_id from endpoint $ep_id"
    gcloud ai endpoints undeploy-model "$ep_id" \
      --deployed-model-id="$dep_id" \
      --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" --quiet || true
  done
done

# 1b. Delete GKE LoadBalancer services (free up LB IPs that block VPC delete)
gcloud container clusters get-credentials "${NAME_PREFIX}-gke" \
  --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" 2>/dev/null || true
kubectl delete svc -n sentinel --all 2>/dev/null || true

# ---------- 2. Destroy in REVERSE order --------------------------------------
# Top-down: peel away workloads first, then ML, then foundation, then globals.
REVERSE_ORDER=(
  18-grafana-dashboard
  17-monitoring
  16-cloudscheduler
  15-cloudrun
  14-compute-engine
  13-gke
  12-vertexai-forecast-endpoint
  11-vertexai-endpoints
  10-vertexai-pipelines
  09-vertexai-tensorboard
  08-vertexai-workbench
  07-secret-manager
  06-pubsub
  05-bigquery
  04-artifact-registry
  03-cloudstorage
  02-iam
  01-vpc
  00-globals
)

for f in "${REVERSE_ORDER[@]}"; do
  destroy_folder "$f" || echo "    (continuing despite error in $f)"
done

# ---------- 3. Optional: nuke the state bucket itself ------------------------
echo ""
read -r -p ">>> Also delete the Terraform state bucket gs://${TFSTATE_BUCKET}? (yes/no): " del_state
if [[ "$del_state" == "yes" ]]; then
  gsutil -m rm -r "gs://${TFSTATE_BUCKET}" || true
  echo ">>> state bucket deleted."
fi

echo ""
echo "============================================================"
echo ">>> teardown complete."
echo "    Project: ${GCP_PROJECT_ID}"
echo "    If you want to delete the GCP project itself:"
echo "      gcloud projects delete ${GCP_PROJECT_ID}"
echo "============================================================"
