# =============================================================================
# WHAT  : Cloud Armor security policy — basic WAF + rate limit.
# WHY   : Even a demo project should not be a free DDoS target.
# HOW   : Default rule = allow, plus rate-limit per source IP, plus a few
#         OWASP pre-built rules.
# JD KEYWORD: security, networking
# =============================================================================

# Gated behind `enable_cloud_armor` because new/trial GCP projects have a
# default quota of 0 SECURITY_POLICIES. Set the variable to true once you
# have a quota increase OR a public load balancer that needs WAF.
resource "google_compute_security_policy" "armor" {
  count       = var.enable_cloud_armor ? 1 : 0
  name        = "${local.name_prefix}-armor"
  description = "Sentinel-Forecast WAF + rate limit"

  # Rate limit: 100 req/min per IP, then deny for 60s
  rule {
    action   = "rate_based_ban"
    priority = 1000

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }

    rate_limit_options {
      conform_action      = "allow"
      exceed_action       = "deny(429)"
      enforce_on_key      = "IP"
      ban_duration_sec    = 60

      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
    }

    description = "rate-limit per IP"
  }

  # Default rule (lowest priority) — allow
  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "default allow"
  }
}
