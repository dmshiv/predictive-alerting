# =============================================================================
# WHAT  : Inputs this folder needs (shared with all folders).
# WHY   : Avoid hard-coding project/region anywhere in the codebase.
# HOW   : start.sh exports TF_VAR_* before invoking terraform.
# =============================================================================
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Default GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Default GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "env_name" {
  description = "Environment suffix (dev | staging | prod)"
  type        = string
  default     = "dev"
}

variable "tfstate_bucket" {
  description = "Bucket holding Terraform remote state (used to read upstream folders)"
  type        = string
}

# Read globals from upstream remote state
data "terraform_remote_state" "globals" {
  backend = "gcs"
  config = {
    bucket = var.tfstate_bucket
    prefix = "00-globals/state"
  }
}

locals {
  name_prefix = data.terraform_remote_state.globals.outputs.name_prefix
}
