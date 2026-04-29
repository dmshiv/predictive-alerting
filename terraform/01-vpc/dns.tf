# =============================================================================
# WHAT  : A private Cloud DNS zone for our internal service names.
# WHY   : So workloads can dial e.g. `triage.sentinel.internal` instead of
#         brittle Cloud Run URLs.
# HOW   : Private visibility = only our VPC can resolve it.
# JD KEYWORD: DNS
# =============================================================================

resource "google_dns_managed_zone" "internal" {
  name        = "${local.name_prefix}-internal"
  dns_name    = "sentinel.internal."
  description = "Private internal DNS zone for Sentinel workloads"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc.id
    }
  }
}
