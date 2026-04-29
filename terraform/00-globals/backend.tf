# =============================================================================
# WHAT  : Tells Terraform to store state in a GCS bucket (not local).
# WHY   : So multiple developers + CI can share state safely with locking.
# HOW   : The bucket name is partial-config; start.sh passes it via
#         `-backend-config="bucket=<name>"`. Each folder uses its own `prefix`.
# =============================================================================

terraform {
  backend "gcs" {
    prefix = "00-globals/state"
    # bucket = passed via -backend-config at init time
  }
}
