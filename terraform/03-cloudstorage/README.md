# 03-cloudstorage

**WHAT:** Five GCS buckets — raw-data, processed, models, tb-logs, code-staging.

**WHY:** Vertex AI Pipelines, Workbench, and our training scripts all need durable, versioned object storage with lifecycle rules to control cost.

**HOW:** Regional buckets, versioning enabled, lifecycle rules per purpose.

**JD KEYWORD:** Cloud Storage

**EXPORTS:** `bucket_*` outputs consumed by every folder that needs to read/write blobs.
