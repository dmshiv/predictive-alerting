# GCP Console Tour

A guided walkthrough of every place to look in the GCP Console after `start.sh`
finishes. Bookmark these links — they're the demo.

> Replace `PROJECT_ID` in URLs below with your real project id.

---

## 1. Vertex AI

### Workbench (your Jupyter sandbox)
- **What:** Managed JupyterLab for interactive EDA.
- **URL:** https://console.cloud.google.com/vertex-ai/workbench/instances?project=PROJECT_ID
- **What to look for:** instance `sentinel-dev-workbench` running. Click **Open JupyterLab** and explore `src/notebooks/`.

### Endpoints (the two AIs)
- **What:** Live serving endpoints for AI #1 and AI #2.
- **URL:** https://console.cloud.google.com/vertex-ai/endpoints?project=PROJECT_ID
- **What to look for:** `sentinel-dev-victim-recommender` (AI #1) and `sentinel-dev-forecaster` (AI #2). Click each → **Logs**, **Metrics**, **Deploy & test**.

### Pipelines (training DAGs)
- **What:** Vertex AI Pipelines (KFP) runs.
- **URL:** https://console.cloud.google.com/vertex-ai/pipelines/runs?project=PROJECT_ID
- **What to look for:** scheduled runs of `sentinel-victim-train` (nightly) and `sentinel-forecaster-train` (every 6h).

### TensorBoard
- **What:** Training metric visualizer.
- **URL:** https://console.cloud.google.com/vertex-ai/experiments/tensorboard-instances?project=PROJECT_ID
- **What to look for:** `sentinel-dev-tensorboard`. After the first training run, you can launch it and see loss curves.

### Model Registry
- **URL:** https://console.cloud.google.com/vertex-ai/models?project=PROJECT_ID
- Compare model versions; promote/demote between them.

---

## 2. Compute & Workloads

### Cloud Run (serverless services)
- **URL:** https://console.cloud.google.com/run?project=PROJECT_ID
- `sentinel-dev-triage` — the orchestrator. Click → **Logs** to see incoming alerts.
- `sentinel-dev-grafana` — the dashboard. Click the **URL** (top-right) to open Grafana.

### GKE (Kubernetes)
- **URL:** https://console.cloud.google.com/kubernetes/list?project=PROJECT_ID
- Cluster `sentinel-dev-gke` (Autopilot). Workloads → namespace `sentinel`:
  - `telemetry-collector` — Pub/Sub → BigQuery
  - `forecast-detector` — runs the per-minute forecaster

### Compute Engine (VMs)
- **URL:** https://console.cloud.google.com/compute/instances?project=PROJECT_ID
- `sentinel-dev-loadgen` — the synthetic shopper. SSH via IAP to inspect logs:
  ```
  gcloud compute ssh sentinel-dev-loadgen --zone=us-central1-a \
    --tunnel-through-iap --project=PROJECT_ID
  sudo journalctl -u sentinel-loadgen -f
  ```

---

## 3. Data

### BigQuery
- **URL:** https://console.cloud.google.com/bigquery?project=PROJECT_ID
- Datasets:
  - `sentinel_dev_features.telemetry_raw` — every metric ever measured
  - `sentinel_dev_features.predictions` — AI #2's forecasts
  - `sentinel_dev_incidents.incidents` — every alert + Gemini report
- **Try this query** (paste in Console):
  ```sql
  SELECT fired_at, metric_name, severity, runbook_id,
         SUBSTR(gemini_report, 1, 200) AS report
    FROM `PROJECT_ID.sentinel_dev_incidents.incidents`
    ORDER BY fired_at DESC LIMIT 20
  ```

### Cloud Storage
- **URL:** https://console.cloud.google.com/storage/browser?project=PROJECT_ID
- Buckets:
  - `*-raw-data` — image/text fixtures
  - `*-processed` — pipeline parquet outputs
  - `*-models` — Vertex AI model artifacts
  - `*-tb-logs` — TensorBoard event files
  - `*-code` — KFP pipeline JSON specs

### Pub/Sub
- **URL:** https://console.cloud.google.com/cloudpubsub/topic/list?project=PROJECT_ID
- Topics: `raw-traffic`, `telemetry`, `incidents`, `retrain-trigger`, `dlq`.

---

## 4. Observability

### Cloud Logging
- **URL:** https://console.cloud.google.com/logs/query?project=PROJECT_ID
- **Filter for predictive alerts:**
  ```
  jsonPayload.event="predictive_alert"
  ```
- **Filter for Gemini calls:**
  ```
  jsonPayload.event="gemini_call"
  ```

### Cloud Monitoring
- **URL:** https://console.cloud.google.com/monitoring/dashboards?project=PROJECT_ID
- Look for **Sentinel · System Overview** (built by `17-monitoring/dashboards.tf`).
- **Alert policies:** https://console.cloud.google.com/monitoring/alerting?project=PROJECT_ID

### Grafana
- **URL:** Run `terraform output -raw grafana_url` in `terraform/15-cloudrun/`.
- Default dashboards: **Sentinel · Overview**, **ML Models**, **Infrastructure**, **Cost**.

---

## 5. Security & IAM

### IAM
- **URL:** https://console.cloud.google.com/iam-admin/serviceaccounts?project=PROJECT_ID
- All `sentinel-dev-*` service accounts have least-privilege roles.

### Secret Manager
- **URL:** https://console.cloud.google.com/security/secret-manager?project=PROJECT_ID
- `sentinel-dev-gemini-api-key`, `sentinel-dev-slack-webhook`, `sentinel-dev-alert-email-target`

### Cloud Armor (WAF)
- **URL:** https://console.cloud.google.com/net-security/securitypolicies?project=PROJECT_ID
- Policy `sentinel-dev-armor` protects future load balancers.

---

## 6. Cost

### Billing
- **URL:** https://console.cloud.google.com/billing?project=PROJECT_ID
- Run a daily breakdown query in BigQuery (export billing first via Billing → Billing export).
