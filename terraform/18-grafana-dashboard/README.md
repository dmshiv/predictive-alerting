# 18-grafana-dashboard

**WHAT:** Stages Grafana dashboard JSON files into Cloud Storage so the Cloud Run Grafana service can read them at boot.

**WHY:** Decouples dashboard config from container image. Edit a JSON and re-apply this folder; no Docker rebuild.

**HOW:** `google_storage_bucket_object` for each dashboard. The Grafana container watches this bucket via a small init script.

**JD KEYWORD:** Grafana, dashboards
