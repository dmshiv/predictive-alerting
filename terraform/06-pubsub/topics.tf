# =============================================================================
# WHAT  : Four Pub/Sub topics (the project's nervous system).
# JD KEYWORD: Pub/Sub
# =============================================================================

locals {
  topics = ["raw-traffic", "telemetry", "incidents", "retrain-trigger"]
}

resource "google_pubsub_topic" "topics" {
  for_each = toset(local.topics)
  name     = "${local.name_prefix}-${each.value}"

  message_retention_duration = "86400s"  # 1 day
}

# Dead letter topic (one shared)
resource "google_pubsub_topic" "dlq" {
  name = "${local.name_prefix}-dlq"
  message_retention_duration = "604800s"  # 7 days
}
