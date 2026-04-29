# =============================================================================
# WHAT  : Values exported for downstream Terraform folders to consume.
# WHY   : Avoids re-typing project_id / region everywhere; uses
#         terraform_remote_state in downstream folders.
# HOW   : Read from another folder via:
#           data "terraform_remote_state" "globals" {
#             backend = "gcs"
#             config  = { bucket = ..., prefix = "00-globals/state" }
#           }
# =============================================================================

output "project_id" {
  value       = var.project_id
  description = "Project where everything lands"
}

output "region" {
  value       = var.region
  description = "Default region"
}

output "zone" {
  value       = var.zone
  description = "Default zone"
}

output "env_name" {
  value       = var.env_name
  description = "Environment suffix"
}

output "name_prefix" {
  value       = "sentinel-${var.env_name}"
  description = "Prefix for resource names so they don't collide with other projects"
}
