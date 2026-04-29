#!/usr/bin/env bash

##builds all our TF cloud infra **

# =============================================================================
# WHAT  : Full end-to-end deploy. Runs each terraform/<NN>-* folder in order,
#         submits Cloud Build for all images, compiles + uploads pipelines,
#         seeds initial models, and prints the demo URLs.
# WHY   : Single command: from `gcloud auth login` to "open Grafana".
# HOW   : Iterates the numbered folders alphabetically (00- through 18-),
#         passing TFSTATE_BUCKET so each can read upstream outputs.
# LAYMAN: Press the big green start button.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ---------- env --------------------------------------------------------------
if [[ ! -f .env ]]; then
  echo "ERROR: .env missing. Run scripts/bootstrap.sh first." >&2
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
: "${ALERT_EMAIL:=}"

NAME_PREFIX="sentinel-${ENV_NAME}"
CODE_BUCKET="${GCP_PROJECT_ID}-${NAME_PREFIX}-code"
MODELS_BUCKET="${GCP_PROJECT_ID}-${NAME_PREFIX}-models"

# ---------- helpers ----------------------------------------------------------
TF_VARS=(
  -var "project_id=${GCP_PROJECT_ID}"
  -var "region=${GCP_REGION}"
  -var "zone=${GCP_ZONE:-${GCP_REGION}-a}"
  -var "env_name=${ENV_NAME}"
  -var "tfstate_bucket=${TFSTATE_BUCKET}"
)

# ---------- robust apply ------------------------------------------------------
# Lock-timeout: if another process holds the state lock, wait up to 5 min
# instead of failing immediately.
TF_LOCK_TIMEOUT="300s"
# Sleep between folders so newly-enabled APIs / freshly-created resources have
# time to fully propagate (esp. APIs in 00-globals).
TF_INTER_FOLDER_SLEEP="${TF_INTER_FOLDER_SLEEP:-5}"
# How many times to retry a failed apply (transient API/quota propagation).
TF_RETRY_MAX="${TF_RETRY_MAX:-3}"

verify_state_exists() {
  local folder="$1"
  local prefix="${folder}/state"
  if ! gsutil ls "gs://${TFSTATE_BUCKET}/${prefix}/default.tfstate" >/dev/null 2>&1; then
    echo "    [verify] WARN: no state file found at gs://${TFSTATE_BUCKET}/${prefix}/" >&2
    return 1
  fi
  echo "    [verify] state OK: gs://${TFSTATE_BUCKET}/${prefix}/default.tfstate"
}

clear_stale_lock() {
  # If a previous run died mid-apply, release any stale lock so we can resume.
  local folder="$1"
  pushd "terraform/${folder}" >/dev/null
  local lock_id
  lock_id=$(terraform force-unlock -force NOTREALID 2>&1 | grep -oP 'ID:\s*\K[0-9a-f-]+' || true)
  if [[ -n "$lock_id" ]]; then
    echo "    [lock] stale lock detected ($lock_id); force-unlocking..."
    terraform force-unlock -force "$lock_id" || true
  fi
  popd >/dev/null
}

apply_folder() {
  local folder="$1"
  local attempt=1

  # Allow user to resume mid-deploy: START_FROM=08-vertexai-workbench ./start.sh
  # skips every folder lexically before it.
  if [[ -n "${START_FROM:-}" ]]; then
    if [[ "$(printf '%s\n%s\n' "$folder" "$START_FROM" | sort | head -1)" == "$folder" \
          && "$folder" != "$START_FROM" ]]; then
      echo ">>> Skipping ${folder}  (START_FROM=${START_FROM})"
      return 0
    fi
  fi

  echo ""
  echo "============================================================"
  echo ">>> Applying ${folder}    (lock-timeout=${TF_LOCK_TIMEOUT}, max retries=${TF_RETRY_MAX})"
  echo "============================================================"

  pushd "terraform/${folder}" >/dev/null

  # Inject per-folder extra vars
  local extra_vars=()
  if [[ "$folder" == "17-monitoring" && -n "$ALERT_EMAIL" ]]; then
    extra_vars+=(-var "alert_email=${ALERT_EMAIL}")
  fi
  if [[ "$folder" == "02-iam" && "${ENABLE_WI_BINDINGS:-false}" == "true" ]]; then
    extra_vars+=(-var "enable_workload_identity_bindings=true")
  fi

  # init is cheap and idempotent; always run before apply
  terraform init -reconfigure \
    -backend-config="bucket=${TFSTATE_BUCKET}" \
    -backend-config="prefix=${folder}/state" \
    -lock-timeout="${TF_LOCK_TIMEOUT}" >/dev/null

  # Retry loop for transient failures (newly-enabled APIs, eventual consistency)
  while (( attempt <= TF_RETRY_MAX )); do
    if terraform apply -auto-approve \
        -lock-timeout="${TF_LOCK_TIMEOUT}" \
        "${TF_VARS[@]}" "${extra_vars[@]}"; then
      break
    fi
    if (( attempt == TF_RETRY_MAX )); then
      echo "    [apply] FAILED after ${TF_RETRY_MAX} attempts on ${folder}" >&2
      popd >/dev/null
      return 1
    fi
    local backoff=$(( attempt * 30 ))
    echo "    [apply] attempt ${attempt}/${TF_RETRY_MAX} failed; sleeping ${backoff}s before retry..."
    sleep "$backoff"
    ((attempt++))
  done

  popd >/dev/null

  # Verify the state file was actually written, then breathe before next folder
  verify_state_exists "$folder" || true
  if (( TF_INTER_FOLDER_SLEEP > 0 )); then
    sleep "${TF_INTER_FOLDER_SLEEP}"
  fi
}

# ---------- 0. tooling sanity -----------------------------------------------
command -v terraform >/dev/null || { echo "install terraform >= 1.6"; exit 1; }
command -v gcloud >/dev/null    || { echo "install gcloud SDK"; exit 1; }
command -v gsutil >/dev/null    || { echo "install gsutil";     exit 1; }

gcloud config set project "${GCP_PROJECT_ID}" --quiet

# ---------- 1. terraform foundation (00 -> 07) ------------------------------
# 00-globals enables ~30 APIs. We MUST give GCP time to fully propagate them
# before any downstream folder tries to use a service.
apply_folder "00-globals"
echo ">>> APIs enabled; sleeping 60s for service propagation across regions..."
sleep 60

for f in 01-vpc 02-iam 03-cloudstorage 04-artifact-registry \
         05-bigquery 06-pubsub 07-secret-manager; do
  apply_folder "$f"
done

# ---------- 2. build + push container images --------------------------------
# DEFAULT: build images LOCALLY (5-10 min on a modern laptop). Cloud Build is
# offered as opt-in (USE_CLOUD_BUILD=true) but is queue-starved on trial GCP
# accounts and can take 30+ min, so we no longer use it by default.
_skip_build=false
if [[ "${SKIP_BUILD:-${SKIP_CLOUDBUILD:-false}}" == "true" ]]; then
  _skip_build=true
fi
if [[ -n "${START_FROM:-}" ]]; then
  if [[ "$(printf '%s\n%s\n' "07-secret-manager" "$START_FROM" | sort | head -1)" == "07-secret-manager" \
        && "$START_FROM" != "07-secret-manager" ]]; then
    _skip_build=true
  fi
fi
if [[ "$_skip_build" == "true" ]]; then
  echo ">>> Skipping image build  (SKIP_BUILD=${SKIP_BUILD:-${SKIP_CLOUDBUILD:-false}}, START_FROM=${START_FROM:-})"
else
  if [[ "${USE_CLOUD_BUILD:-false}" == "true" ]]; then
    echo ""
    echo "============================================================"
    echo ">>> Submitting Cloud Build (5 images, can take 8-30 min on trial accounts)"
    echo "============================================================"
    gcloud builds submit \
      --project="${GCP_PROJECT_ID}" \
      --config=docker/cloudbuild.yaml \
      --substitutions=_REGION="${GCP_REGION}",_REPO="sentinel-images" \
      .
  else
    echo ""
    echo "============================================================"
    echo ">>> Building 5 images locally (5-10 min). Set USE_CLOUD_BUILD=true to use Cloud Build instead."
    echo "============================================================"
    command -v docker >/dev/null || { echo "ERROR: docker required for local build. Install Docker or set USE_CLOUD_BUILD=true." >&2; exit 1; }
    ./scripts/build_local.sh
  fi

  # ---------- 3. compile + upload pipelines ---------------------------------
  echo ""
  echo ">>> Compiling KFP pipelines + uploading to gs://${CODE_BUCKET}/pipelines/"
  python -m src.pipelines.compile \
    --upload-to-gcs \
    --bucket "${CODE_BUCKET}" \
    --project-id "${GCP_PROJECT_ID}"

  # ---------- 4. upload traffic_generator.py to code bucket -----------------
  gsutil cp src/ingestion/traffic_generator.py "gs://${CODE_BUCKET}/traffic_generator.py" || true
  gsutil cp src/ingestion/chaos_modes.py        "gs://${CODE_BUCKET}/chaos_modes.py"        || true
fi  # end skip-block for steps 2-4

# ---------- 5. terraform ML + workload (08 -> 13-gke) ----------------------
for f in 08-vertexai-workbench 09-vertexai-tensorboard 10-vertexai-pipelines \
         11-vertexai-endpoints 12-vertexai-forecast-endpoint 13-gke; do
  apply_folder "$f"
done

# ---------- 5b. Wait for GKE cluster to actually be RUNNING -----------------
# `terraform apply` returns when the GKE resource is created, but the
# Workload Identity pool (PROJECT.svc.id.goog) takes another ~30-60s to be
# usable. Block until the cluster shows status=RUNNING.
echo ""
echo ">>> Waiting for GKE cluster to reach RUNNING state..."
for i in {1..30}; do
  status=$(gcloud container clusters describe "${NAME_PREFIX}-gke" \
    --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" \
    --format='value(status)' 2>/dev/null || echo "PENDING")
  if [[ "$status" == "RUNNING" ]]; then
    echo ">>> GKE cluster is RUNNING."
    break
  fi
  echo "    [${i}/30] cluster status=${status}, waiting 10s..."
  sleep 10
done

# Extra 30s breather so the WI identity pool is registered server-side
sleep 30

# ---------- 5c. Second-pass IAM: enable Workload Identity bindings ----------
echo ""
echo ">>> Re-applying 02-iam with Workload Identity bindings enabled..."
ENABLE_WI_BINDINGS=true apply_folder "02-iam"

# ---------- 5c. terraform workload + observability (14 -> 18) --------------
for f in 14-compute-engine 15-cloudrun 16-cloudscheduler 17-monitoring \
         18-grafana-dashboard; do
  apply_folder "$f"
done

# ---------- 6. seed models + register in Vertex AI + apply GKE detector -----
# This single script does:
#   1. Train+upload synthetic VICTIM model artefact to GCS
#   2. Register the VICTIM model in Vertex AI Model Registry
#   3. Deploy the VICTIM model to its endpoint (created by terraform/11)
#   4. Train+upload synthetic FORECASTER model (.keras + norm_stats.npz)
#   5. Apply the forecast-detector Deployment to GKE (with placeholders
#      substituted from this project/region/env)
# All steps are idempotent — re-running will replace existing models.
if [[ "${SKIP_SEED:-false}" == "true" ]]; then
  echo ">>> Skipping model seed (SKIP_SEED=true)"
else
  echo ""
  echo "============================================================"
  echo ">>> Seeding models + applying detector pod (~5-8 min)"
  echo "============================================================"
  ./scripts/seed_models.sh || \
    echo "    (seed_models failed; you can re-run manually: ./scripts/seed_models.sh)"
fi

# ---------- 7. print demo URLs ----------------------------------------------
TRIAGE_URL="$(cd terraform/15-cloudrun && terraform output -raw triage_url 2>/dev/null || echo '')"
GRAFANA_URL="$(cd terraform/15-cloudrun && terraform output -raw grafana_url 2>/dev/null || echo '')"

echo ""
echo "============================================================"
echo ">>> deploy complete."
echo "============================================================"
echo "    Project        : ${GCP_PROJECT_ID}"
echo "    Region         : ${GCP_REGION}"
echo "    Grafana        : ${GRAFANA_URL}"
echo "    Triage (auth)  : ${TRIAGE_URL}"
echo "    Console (Vertex): https://console.cloud.google.com/vertex-ai?project=${GCP_PROJECT_ID}"
echo ""
echo "    Demo:  ./scripts/chaos_inject.py --mode=drift"
echo "    Smoke: ./scripts/smoke_test.sh"
echo "    Stop:  ./scripts/stop.sh   (saves money overnight)"
