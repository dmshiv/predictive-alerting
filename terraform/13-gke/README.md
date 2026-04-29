# 13-gke

**WHAT:** A private GKE Autopilot cluster + manifests for the telemetry collector and detector pods.

**WHY:** GKE Autopilot manages nodes for us; we just submit pods. Used to run the always-on telemetry collector (Pub/Sub -> BigQuery) and the per-minute forecast-check worker.

**HOW:** Private cluster on the VPC, Workload Identity enabled, kubectl manifests applied via the kubernetes provider.

**JD KEYWORD:** Kubernetes / GKE
