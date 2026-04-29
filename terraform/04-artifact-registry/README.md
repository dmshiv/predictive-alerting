# 04-artifact-registry

**WHAT:** A regional Docker repository in Artifact Registry.

**WHY:** Cloud Build pushes our four container images here; GKE / Cloud Run / Vertex pull from here.

**HOW:** Single `google_artifact_registry_repository` (Docker format) + IAM for our SAs.

**EXPORTS:** `repo_url` (e.g. `us-central1-docker.pkg.dev/PROJECT/sentinel-images`)
