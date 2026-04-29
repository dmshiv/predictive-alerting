# 10-vertexai-pipelines

**WHAT:** Storage/permissions for KFP pipelines + a Cloud Scheduler trigger that invokes them on a schedule.

**WHY:** Pipelines themselves are compiled JSON files (under `src/pipelines/`) uploaded by `start.sh`. This folder sets up the schedule + IAM so they can run unattended.

**HOW:** A Cloud Scheduler HTTP job that POSTs to the Vertex AI Pipelines API to start a pipeline run. The compiled spec lives in GCS.

**JD KEYWORD:** Vertex AI Pipelines, KFP
