# 11-vertexai-endpoints  (AI #1)

**WHAT:** Vertex AI Endpoint shell where AI #1 (the multi-modal recommender) will be served. Plus a Vertex AI Model Monitoring config for that endpoint.

**WHY:** The endpoint is created here as an empty shell; the actual model is uploaded + deployed by `src/pipelines/victim_train_pipeline.py` running on Vertex Pipelines after `start.sh` triggers it.

**HOW:** `google_vertex_ai_endpoint` (just the shell). Models are deployed by the pipeline via the Vertex AI SDK.

**JD KEYWORDS:** Vertex AI Endpoints, Vertex AI Model Monitoring
