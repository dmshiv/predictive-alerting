# =============================================================================
# WHAT  : Inputs every Terraform folder needs.
# WHY   : So we don't hard-code project IDs anywhere.
# HOW   : start.sh exports TF_VAR_project_id / TF_VAR_region / TF_VAR_zone /
#         TF_VAR_env_name from your .env file before running `terraform apply`.
# =============================================================================

variable "project_id" {
  description = "GCP project ID (from .env)"
  type        = string
}

variable "region" {
  description = "Default GCP region (e.g. us-central1)"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Default GCP zone (e.g. us-central1-a)"
  type        = string
  default     = "us-central1-a"
}

variable "env_name" {
  description = "Environment suffix (dev | staging | prod)"
  type        = string
  default     = "dev"
}

variable "tfstate_bucket" {
  description = "GCS bucket holding remote terraform state (created by bootstrap.sh)"
  type        = string
}
