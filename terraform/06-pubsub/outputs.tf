output "topics"          { value = { for k, t in google_pubsub_topic.topics : k => t.name } }
output "topic_raw"       { value = google_pubsub_topic.topics["raw-traffic"].name }
output "topic_telemetry" { value = google_pubsub_topic.topics["telemetry"].name }
output "topic_incidents" { value = google_pubsub_topic.topics["incidents"].name }
output "topic_retrain"   { value = google_pubsub_topic.topics["retrain-trigger"].name }
output "topic_dlq"       { value = google_pubsub_topic.dlq.name }
output "sub_ingestion_raw"       { value = google_pubsub_subscription.ingestion_raw.name }
output "sub_ingestion_telemetry" { value = google_pubsub_subscription.ingestion_telemetry.name }
output "sub_triage_incidents"    { value = google_pubsub_subscription.triage_incidents.name }
