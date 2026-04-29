# =============================================================================
# WHAT  : Subscriptions for each consumer.
# WHY   : Each consumer needs its own sub so they don't steal each other's msgs.
# =============================================================================

# Telemetry collector (GKE pod) consumes raw-traffic + telemetry
resource "google_pubsub_subscription" "ingestion_raw" {
  name  = "${local.name_prefix}-ingestion-raw"
  topic = google_pubsub_topic.topics["raw-traffic"].name
  ack_deadline_seconds = 30

  expiration_policy { ttl = "" }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = 5
  }
}

resource "google_pubsub_subscription" "ingestion_telemetry" {
  name  = "${local.name_prefix}-ingestion-telemetry"
  topic = google_pubsub_topic.topics["telemetry"].name
  ack_deadline_seconds = 30

  expiration_policy { ttl = "" }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = 5
  }
}

# Triage service subscribes to incidents (push to Cloud Run URL filled in by 15-cloudrun)
resource "google_pubsub_subscription" "triage_incidents" {
  name  = "${local.name_prefix}-triage-incidents"
  topic = google_pubsub_topic.topics["incidents"].name
  ack_deadline_seconds = 60

  expiration_policy { ttl = "" }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = 5
  }
}

# Pipeline retrain trigger
resource "google_pubsub_subscription" "pipeline_retrain" {
  name  = "${local.name_prefix}-pipeline-retrain"
  topic = google_pubsub_topic.topics["retrain-trigger"].name
  ack_deadline_seconds = 600
  expiration_policy { ttl = "" }
}

# DLQ subscription so we can inspect failed messages
resource "google_pubsub_subscription" "dlq_inspect" {
  name  = "${local.name_prefix}-dlq-inspect"
  topic = google_pubsub_topic.dlq.name
  ack_deadline_seconds = 60
  expiration_policy { ttl = "" }
}
