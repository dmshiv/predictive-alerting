# =============================================================================
# WHAT  : Firewall rules — deny by default, allow internal + IAP SSH.
# WHY   : "Default-allow" rules are a TSE's nightmare. We start strict.
# HOW   : One allow-internal rule (10.10.0.0/24 talks to itself), one
#         allow-IAP rule (so we can SSH via Identity-Aware Proxy without
#         opening port 22 to the world), one allow-health-check rule.
# JD KEYWORD: firewalling, security
# =============================================================================

resource "google_compute_firewall" "allow_internal" {
  name      = "${local.name_prefix}-allow-internal"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.10.0.0/24", "10.20.0.0/16", "10.30.0.0/20"]
}

resource "google_compute_firewall" "allow_iap_ssh" {
  name      = "${local.name_prefix}-allow-iap-ssh"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Google's IAP IP range — lets you `gcloud compute ssh` without public IPs
  source_ranges = ["35.235.240.0/20"]
}

resource "google_compute_firewall" "allow_health_checks" {
  name      = "${local.name_prefix}-allow-hc"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
  }

  # Google's load-balancer health-check IP ranges
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
}
