#!/usr/bin/env bash
# =============================================================================
# WHAT  : Build all 5 container images LOCALLY and push to Artifact Registry.
# WHY   : Cloud Build queues for 5-30 min on trial accounts. Building locally
#         with the host Docker daemon is 5-10x faster end-to-end.
# HOW   : Auth docker for AR -> serial docker build -> serial docker push.
# USAGE : ./scripts/build_local.sh         # builds all 5
#         ./scripts/build_local.sh victim  # builds just one
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
: "${GCP_REGION:=us-central1}"

REPO="sentinel-images"
REGISTRY="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${REPO}"

# ---------- auth -------------------------------------------------------------
echo ">>> Authenticating docker for ${GCP_REGION}-docker.pkg.dev..."
gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet

# ---------- image map (id -> dockerfile) -------------------------------------
declare -A IMAGES=(
  [traffic-gen]="docker/traffic-gen.Dockerfile"
  [grafana]="docker/grafana.Dockerfile"
  [triage]="docker/triage.Dockerfile"
  [forecaster]="docker/forecaster.Dockerfile"
  [victim]="docker/victim.Dockerfile"
)

# Build order: light -> heavy so failures surface fast
ORDER=(traffic-gen grafana triage forecaster victim)

# Filter to a single image if argument given
if [[ $# -gt 0 ]]; then
  ORDER=("$1")
  if [[ -z "${IMAGES[$1]:-}" ]]; then
    echo "ERROR: unknown image '$1'. Choices: ${!IMAGES[*]}" >&2
    exit 1
  fi
fi

# ---------- build + push -----------------------------------------------------
START_TS=$(date +%s)
for name in "${ORDER[@]}"; do
  dockerfile="${IMAGES[$name]}"
  tag_latest="${REGISTRY}/${name}:latest"
  tag_sha="${REGISTRY}/${name}:$(date +%Y%m%d-%H%M%S)"

  echo ""
  echo "============================================================"
  echo ">>> [${name}] building from ${dockerfile}"
  echo "============================================================"
  t0=$(date +%s)
  docker build -f "$dockerfile" -t "$tag_latest" -t "$tag_sha" .
  echo ">>> [${name}] build took $(( $(date +%s) - t0 ))s"

  echo ">>> [${name}] pushing :latest and :timestamp ..."
  t1=$(date +%s)
  docker push "$tag_latest"
  docker push "$tag_sha"
  echo ">>> [${name}] push took $(( $(date +%s) - t1 ))s"
done

echo ""
echo "============================================================"
echo ">>> Local build complete in $(( $(date +%s) - START_TS ))s"
echo "============================================================"
echo "    Images pushed to: ${REGISTRY}"
echo ""
if [[ ${#ORDER[@]} -eq 1 ]]; then
  # Single-image rebuild: terraform is already applied, just bounce workload.
  case "${ORDER[0]}" in
    traffic-gen)
      echo "    Next step (rebuilt only ${ORDER[0]}):"
      echo "      kubectl rollout restart deployment/telemetry-collector -n sentinel"
      echo "      gcloud compute instances reset sentinel-dev-loadgen --zone=us-central1-a --project=\${GCP_PROJECT_ID}"
      ;;
    triage|grafana)
      echo "    Next step (rebuilt only ${ORDER[0]}):"
      echo "      gcloud run services update sentinel-dev-${ORDER[0]} --region=us-central1 --project=\${GCP_PROJECT_ID} --update-env-vars=BUMP=$(date +%s)"
      ;;
    victim|forecaster)
      echo "    Next step (rebuilt only ${ORDER[0]}):"
      echo "      Re-run the Vertex AI deployment pipeline OR redeploy the model on the endpoint."
      ;;
  esac
else
  # Full rebuild: only useful on a clean project.
  echo "    Next step (full rebuild):"
  echo "      SKIP_CLOUDBUILD=true START_FROM=04-artifact-registry ./scripts/start.sh"
fi
