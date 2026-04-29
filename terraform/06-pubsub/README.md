# 06-pubsub

**WHAT:** Pub/Sub topics + subscriptions + dead-letter queues for the message backbone.

**WHY:** Decouples producers from consumers — load-gen publishes traffic events; the GKE telemetry collector consumes them; the triage service subscribes to incidents.

**TOPICS:** `raw-traffic`, `telemetry`, `incidents`, `retrain-trigger`
