# =============================================================================
# WHAT  : Terraform + provider versions for 13-gke (also needs kubernetes).
# =============================================================================
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google      = { source = "hashicorp/google",      version = "~> 5.40" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 5.40" }
    kubernetes  = { source = "hashicorp/kubernetes",  version = "~> 2.32" }
  }
}
