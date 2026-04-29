# =============================================================================
# WHAT  : GCS-backed Terraform state for this folder.
# WHY   : Shared, locked, durable state.
# HOW   : Bucket name is provided at init time:
#           terraform init -backend-config="bucket=${TFSTATE_BUCKET}"
# =============================================================================
terraform {
  backend "gcs" {
    prefix = "03-cloudstorage/state"
    # bucket = passed via -backend-config at init time
  }
}
