#!/usr/bin/env bash
# =============================================================================
# WHAT  : One-shot script to "finish" the deployment after `start.sh` and
#         `build_local.sh`. It does the things that aren't terraform infra:
#           1. Train a synthetic victim model and upload to GCS.
#           2. Register the model in Vertex AI Model Registry.
#           3. Deploy it to the existing victim-recommender endpoint.
#           4. Apply the forecast-detector Kubernetes Deployment on GKE.
#           5. Smoke-publish an incident through Pub/Sub to validate triage.
#
# WHY   : `start.sh` / terraform only stand up empty endpoints + cluster.
#         The actual ML serving + detection pods need to be deployed separately
#         once the registry has images. This script does that in one shot.
#
# HOW   : Uses the already-built victim Docker image (which has torch + numpy)
#         to train + upload the model artefact, then uses `gcloud ai` CLI to
#         create/deploy a Vertex Model.
#
# Prereqs:
#   - `./scripts/start.sh` already ran successfully (folders 00-18 applied).
#   - `./scripts/build_local.sh` already pushed all 5 images to Artifact Registry.
#   - `gcloud auth login` + `gcloud config set project sentinel-forecast-2544`.
# =============================================================================
set -euo pipefail

# --- Configuration (defaults match the rest of the project) -----------------
PROJECT_ID="${GCP_PROJECT_ID:-sentinel-forecast-2544}"
REGION="${GCP_REGION:-us-central1}"
NAME_PREFIX="${NAME_PREFIX:-sentinel-dev}"

REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/sentinel-images"
VICTIM_IMG="${REGISTRY}/victim:latest"
FORECASTER_IMG="${REGISTRY}/forecaster:latest"

MODELS_BUCKET="${PROJECT_ID}-${NAME_PREFIX}-models"
MODEL_GCS_PATH="gs://${MODELS_BUCKET}/victim"
ENDPOINT_DISPLAY_NAME="${NAME_PREFIX}-victim-recommender"
MODEL_DISPLAY_NAME="${NAME_PREFIX}-victim"

# --- Sanity --------------------------------------------------------------------
command -v docker >/dev/null  || { echo "docker required"; exit 1; }
command -v gcloud >/dev/null  || { echo "gcloud required"; exit 1; }
command -v kubectl >/dev/null || { echo "kubectl required"; exit 1; }

echo ">>> Using project=${PROJECT_ID}, region=${REGION}"
echo ">>> Models bucket: gs://${MODELS_BUCKET}"
gcloud storage ls "gs://${MODELS_BUCKET}/" >/dev/null 2>&1 || {
  echo "ERROR: bucket gs://${MODELS_BUCKET} does not exist. Run start.sh first." >&2
  exit 1
}

# =============================================================================
# 1. TRAIN + UPLOAD VICTIM MODEL ARTEFACT
# =============================================================================
echo ""
echo "======================================================================"
echo ">>> [1/5] Training synthetic victim model inside the victim container"
echo "======================================================================"

# We run the training inline inside the already-built victim image
# (which has torch + numpy + google-cloud-storage). This avoids needing
# torch on the host and avoids a 20-min KFP pipeline run.
TRAIN_PY=$(cat <<'PYEOF'
import io, os, numpy as np, torch
from torch import nn
from google.cloud import storage

PROJECT = os.environ["PROJECT_ID"]
BUCKET  = os.environ["MODELS_BUCKET"]
N_PRODUCTS = 200

print(f"[train] project={PROJECT} bucket=gs://{BUCKET} n_products={N_PRODUCTS}")

rng = np.random.default_rng(0)
text_emb  = torch.from_numpy(rng.standard_normal((N_PRODUCTS, 768)).astype("float32"))
image_emb = torch.from_numpy(rng.standard_normal((N_PRODUCTS, 1024)).astype("float32"))

class Tower(nn.Module):
    def __init__(self, td=768, im=1024, h=512, o=256):
        super().__init__()
        self.net = nn.Sequential(nn.Linear(td+im, h), nn.ReLU(), nn.Linear(h, o))
    def forward(self, t, i):
        return torch.nn.functional.normalize(self.net(torch.cat([t, i], dim=-1)), dim=-1)

qt, ct = Tower(), Tower()
opt = torch.optim.Adam(list(qt.parameters()) + list(ct.parameters()), lr=1e-3)
for epoch in range(3):
    idx = torch.randperm(N_PRODUCTS)[:64]
    q = qt(text_emb[idx] + 0.05*torch.randn_like(text_emb[idx]),
           image_emb[idx] + 0.05*torch.randn_like(image_emb[idx]))
    c = ct(text_emb[idx], image_emb[idx])
    scores = q @ c.t()
    loss = torch.nn.functional.cross_entropy(scores, torch.arange(scores.size(0)))
    opt.zero_grad(); loss.backward(); opt.step()
    print(f"[train] epoch={epoch} loss={loss.item():.4f}")

artefact = {
    # Keys must match TwoTowerRecommender's submodule names (query_tower / candidate_tower)
    # so model.load_state_dict() succeeds inside src/victim_model/serve.py.
    "model_state": {**{f"query_tower.{k}": v for k,v in qt.state_dict().items()},
                    **{f"candidate_tower.{k}": v for k,v in ct.state_dict().items()}},
    "tower_config": {"text_dim": 768, "image_dim": 1024, "hidden": 512, "output": 256},
    "review_emb":     text_emb.numpy(),
    "image_emb":      image_emb.numpy(),
    "product_ids":    [f"p{i:04d}" for i in range(N_PRODUCTS)],
    "product_titles": [f"Product {i}" for i in range(N_PRODUCTS)],
}
torch.save(artefact, "/tmp/victim_model.pt")
print(f"[train] saved /tmp/victim_model.pt ({os.path.getsize('/tmp/victim_model.pt')/1e6:.1f} MB)")

# Upload to GCS
client = storage.Client(project=PROJECT)
client.bucket(BUCKET).blob("victim/victim_model.pt").upload_from_filename("/tmp/victim_model.pt")
print(f"[train] uploaded to gs://{BUCKET}/victim/victim_model.pt")
PYEOF
)

# Mount ADC so the container can authenticate to GCS as you.
ADC_FILE="${HOME}/.config/gcloud/application_default_credentials.json"
if [[ ! -f "$ADC_FILE" ]]; then
  echo ">>> Acquiring ADC (one-time interactive gcloud auth) ..."
  gcloud auth application-default login
fi

docker run --rm \
  -e PROJECT_ID="${PROJECT_ID}" \
  -e MODELS_BUCKET="${MODELS_BUCKET}" \
  -e GOOGLE_APPLICATION_CREDENTIALS=/adc.json \
  -v "${ADC_FILE}:/adc.json:ro" \
  --entrypoint python "${VICTIM_IMG}" -c "${TRAIN_PY}"

# =============================================================================
# 2. REGISTER MODEL IN VERTEX AI + DEPLOY TO ENDPOINT
# =============================================================================
echo ""
echo "======================================================================"
echo ">>> [2/5] Registering model in Vertex AI Model Registry"
echo "======================================================================"

# Find existing model with same display name (idempotency) — list returns empty if none.
EXISTING_MODEL_ID=$(gcloud ai models list --region="${REGION}" --project="${PROJECT_ID}" \
  --filter="displayName=${MODEL_DISPLAY_NAME}" --format="value(name.basename())" | head -1 || true)

if [[ -n "${EXISTING_MODEL_ID}" ]]; then
  # Vertex requires the full resource name for --parent-model, not just the bare numeric ID.
  PARENT_MODEL="projects/${PROJECT_ID}/locations/${REGION}/models/${EXISTING_MODEL_ID}"
  echo ">>> Model '${MODEL_DISPLAY_NAME}' already exists (id=${EXISTING_MODEL_ID}); uploading new version."
  MODEL_ID=$(gcloud ai models upload \
    --region="${REGION}" --project="${PROJECT_ID}" \
    --display-name="${MODEL_DISPLAY_NAME}" \
    --parent-model="${PARENT_MODEL}" \
    --container-image-uri="${VICTIM_IMG}" \
    --container-predict-route="/predict" \
    --container-health-route="/healthz" \
    --container-ports=8080 \
    --container-env-vars="GCP_PROJECT_ID=${PROJECT_ID},GCP_REGION=${REGION},ENV_NAME=${NAME_PREFIX#sentinel-}" \
    --artifact-uri="${MODEL_GCS_PATH}" \
    --format="value(model)")
else
  echo ">>> Uploading new model '${MODEL_DISPLAY_NAME}'."
  MODEL_ID=$(gcloud ai models upload \
    --region="${REGION}" --project="${PROJECT_ID}" \
    --display-name="${MODEL_DISPLAY_NAME}" \
    --container-image-uri="${VICTIM_IMG}" \
    --container-predict-route="/predict" \
    --container-health-route="/healthz" \
    --container-ports=8080 \
    --container-env-vars="GCP_PROJECT_ID=${PROJECT_ID},GCP_REGION=${REGION},ENV_NAME=${NAME_PREFIX#sentinel-}" \
    --artifact-uri="${MODEL_GCS_PATH}" \
    --format="value(model)")
fi
MODEL_ID="${MODEL_ID##*/}"
echo ">>> Model id: ${MODEL_ID}"

echo ""
echo "======================================================================"
echo ">>> [3/5] Deploying model to endpoint '${ENDPOINT_DISPLAY_NAME}'"
echo "======================================================================"

ENDPOINT_ID=$(gcloud ai endpoints list --region="${REGION}" --project="${PROJECT_ID}" \
  --filter="displayName=${ENDPOINT_DISPLAY_NAME}" --format="value(name.basename())" | head -1)
if [[ -z "${ENDPOINT_ID}" ]]; then
  echo "ERROR: endpoint '${ENDPOINT_DISPLAY_NAME}' missing — did 11-vertexai-endpoints apply?" >&2
  exit 1
fi
echo ">>> Endpoint id: ${ENDPOINT_ID}"

# If a model is already deployed, undeploy first (we replace).
EXISTING_DEPLOYMENT=$(gcloud ai endpoints describe "${ENDPOINT_ID}" \
  --region="${REGION}" --project="${PROJECT_ID}" \
  --format="value(deployedModels[0].id)" 2>/dev/null || true)
if [[ -n "${EXISTING_DEPLOYMENT}" ]]; then
  echo ">>> Undeploying existing deployedModel id=${EXISTING_DEPLOYMENT}"
  gcloud ai endpoints undeploy-model "${ENDPOINT_ID}" \
    --region="${REGION}" --project="${PROJECT_ID}" \
    --deployed-model-id="${EXISTING_DEPLOYMENT}" --quiet || true
fi

gcloud ai endpoints deploy-model "${ENDPOINT_ID}" \
  --region="${REGION}" --project="${PROJECT_ID}" \
  --model="${MODEL_ID}" \
  --display-name="${MODEL_DISPLAY_NAME}-deployment" \
  --machine-type="n1-standard-2" \
  --min-replica-count=1 --max-replica-count=2 \
  --traffic-split=0=100

echo ">>> Victim deployed to endpoint ${ENDPOINT_ID}"

# =============================================================================
# 3b. TRAIN + UPLOAD FORECASTER MODEL ARTEFACT
# =============================================================================
# The forecaster pod loads gs://<MODELS_BUCKET>/forecaster/model.keras and
# norm_stats.npz on startup. If they don't exist the pod CrashLoops, so we
# train + upload before applying the GKE Deployment below.
echo ""
echo "======================================================================"
echo ">>> [3b/5] Training synthetic forecaster model inside the forecaster container"
echo "======================================================================"

docker run --rm \
  -e PROJECT_ID="${PROJECT_ID}" \
  -e GCP_PROJECT_ID="${PROJECT_ID}" \
  -e GCP_REGION="${REGION}" \
  -e ENV_NAME="${NAME_PREFIX#sentinel-}" \
  -e GOOGLE_APPLICATION_CREDENTIALS=/adc.json \
  -v "${ADC_FILE}:/adc.json:ro" \
  --entrypoint python "${FORECASTER_IMG}" -m src.forecaster.train_forecaster \
  --upload-to-gcs --epochs 5 --hours 24 --lookback 60 --horizon 120 \
  || echo "    (forecaster train failed; detector will retry on pod restart)"

# =============================================================================
# 4. DEPLOY FORECAST-DETECTOR POD ON GKE
# =============================================================================
echo ""
echo "======================================================================"
echo ">>> [4/5] Applying forecast-detector Deployment on GKE"
echo "======================================================================"

# Make sure kubectl is pointed at our cluster
gcloud container clusters get-credentials "${NAME_PREFIX}-gke" \
  --region="${REGION}" --project="${PROJECT_ID}" >/dev/null

# Render the manifest with the real image URI + project/region/env, then apply.
sed -e "s|REPLACED_BY_TERRAFORM/forecaster:latest|${FORECASTER_IMG}|" \
    -e "s|__PROJECT_ID__|${PROJECT_ID}|g" \
    -e "s|__REGION__|${REGION}|g" \
    -e "s|__ENV_NAME__|${NAME_PREFIX#sentinel-}|g" \
  terraform/13-gke/manifests/detector-deployment.yaml \
  | kubectl apply -f -

kubectl rollout status deployment/forecast-detector -n sentinel --timeout=180s
echo ">>> forecast-detector running:"
kubectl get pods -n sentinel -l app=forecast-detector

# =============================================================================
# 5. SUMMARY
# =============================================================================
echo ""
echo "======================================================================"
echo ">>> [5/5] DONE"
echo "======================================================================"
echo ""
echo "    Vertex AI victim endpoint    : ${ENDPOINT_ID} (deployed)"
echo "    Vertex AI Model id           : ${MODEL_ID}"
echo "    GKE forecast-detector        : up"
echo "    GKE telemetry-collector      : up (already streaming to BQ)"
echo "    VM loadgen                   : publishing to Pub/Sub"
echo ""
echo "    Smoke-test the triage flow (incident_id, fired_at, endpoint_id,"
echo "    metric_name, severity are all REQUIRED by the BQ schema + /alert handler):"
echo "      INCIDENT_ID=\"smoke-\$(date +%s)\""
echo "      NOW=\$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "      gcloud pubsub topics publish ${NAME_PREFIX}-incidents \\"
echo "        --project=${PROJECT_ID} \\"
echo "        --message=\"{\\\"incident_id\\\":\\\"\${INCIDENT_ID}\\\",\\\"fired_at\\\":\\\"\${NOW}\\\",\\\"endpoint_id\\\":\\\"victim-recommender\\\",\\\"metric_name\\\":\\\"latency_ms\\\",\\\"severity\\\":\\\"WARNING\\\",\\\"predicted_breach_at\\\":\\\"\${NOW}\\\",\\\"feature_fingerprint\\\":{}}\""
echo ""
echo "    Then read triage Cloud Run logs:"
echo "      gcloud run services logs read ${NAME_PREFIX}-triage \\"
echo "        --region=${REGION} --project=${PROJECT_ID} --limit=40"
echo ""
echo "    And check BigQuery (column is 'fired_at', not 'event_time'):"
echo "      bq query --project_id=${PROJECT_ID} --use_legacy_sql=false \\"
echo "        \"SELECT incident_id, fired_at, severity, metric_name, runbook_id \\"
echo "         FROM \\\`${PROJECT_ID}.sentinel_${NAME_PREFIX#sentinel-}_incidents.incidents\\\` \\"
echo "         ORDER BY fired_at DESC LIMIT 5\""
