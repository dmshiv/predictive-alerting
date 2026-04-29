# =============================================================================
# WHAT  : Vertex AI Model Monitoring placeholder note.
# WHY   : Model Monitoring jobs are bound to a deployed model version. Since
#         the model is deployed at runtime by the pipeline, the monitoring
#         job is created by the pipeline component too (see
#         `src/pipelines/components/register_model.py`).
# HOW   : This file documents the intent and exports the endpoint ID so the
#         pipeline knows where to attach the monitoring job.
# JD KEYWORD: Vertex AI Model Monitoring
# =============================================================================

# (Intentionally empty — the monitoring job is created post-deploy.)
