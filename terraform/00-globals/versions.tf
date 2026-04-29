# =============================================================================
# WHAT  : Terraform + provider version pins.
# WHY   : Reproducible deploys — same provider version every time.
# HOW   : All folders share these pins (copy-paste; intentional, not a module,
#         so you can read each folder standalone).
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.40"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.40"
    }
  }
}
