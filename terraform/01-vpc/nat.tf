# =============================================================================
# WHAT  : Cloud Router + Cloud NAT.
# WHY   : Private VMs (no public IP) still need to reach the internet to pull
#         packages, container images, and Gemini API. NAT does that securely.
# HOW   : Auto-allocate NAT IPs, log only errors (cheap).
# JD KEYWORD: routing, networking
# =============================================================================

resource "google_compute_router" "router" {
  name    = "${local.name_prefix}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${local.name_prefix}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
