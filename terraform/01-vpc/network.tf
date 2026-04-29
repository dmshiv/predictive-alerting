# =============================================================================
# WHAT  : Custom-mode VPC + a /24 subnet in the default region.
# WHY   : Custom-mode lets us pick our own IP ranges; auto-mode allocates by
#         default in every region (wasteful and surprising).
# HOW   : One subnet now; add more for multi-region later.
# JD KEYWORD: TCP/IP, routing
# =============================================================================

resource "google_compute_network" "vpc" {
  name                    = "${local.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "subnet" {
  name                     = "${local.name_prefix}-subnet"
  ip_cidr_range            = "10.10.0.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true   # so private VMs can call GCS/Vertex without public IP

  # Secondary ranges for GKE pods + services (used by 13-gke)
  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.20.0.0/16"
  }
  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.30.0.0/20"
  }
}
