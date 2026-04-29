"""
============================================================
WHAT  : Synthetic shopper traffic generator. Runs as a
        systemd service on the Compute Engine VM.
WHY   : Always-on baseline traffic so dashboards never go
        empty AND so the forecaster has data to learn from.
HOW   : Reads its current "mode" from VM metadata
        (chaos_inject.py flips this), generates a sample,
        publishes to Pub/Sub `raw-traffic` topic, and also
        writes synthetic telemetry to `telemetry` topic.
LAYMAN: Pretends to be 30-200 shoppers per second clicking
        around the store, so the rest of the system has
        something to react to.
============================================================
"""
from __future__ import annotations

import os
import random
import time
import uuid
from dataclasses import asdict
from datetime import datetime, timezone

# Local imports (work both as `python -m src.ingestion.traffic_generator`
# and as a single-file script copied to the VM).
try:
    from src.ingestion.chaos_modes import get_generator, sleep_between
    from src.utils.config import get_config
    from src.utils.logging_config import setup_logging
    from src.utils.pubsub_client import Publisher
except ImportError:  # running as standalone on the VM
    import sys
    sys.path.insert(0, "/opt/sentinel")
    from chaos_modes import get_generator, sleep_between  # type: ignore
    # Minimal inline fallbacks for VM mode:
    from google.cloud import pubsub_v1
    import logging
    logging.basicConfig(level="INFO", format='{"severity":"%(levelname)s","msg":"%(message)s"}')

import requests

log_name = __name__
import logging
log = logging.getLogger(log_name)


def read_mode_from_metadata() -> str:
    """VM metadata server holds the current chaos mode. chaos_inject.py
    flips it via `gcloud compute instances add-metadata`."""
    try:
        r = requests.get(
            "http://metadata.google.internal/computeMetadata/v1/instance/attributes/sentinel-mode",
            headers={"Metadata-Flavor": "Google"},
            timeout=2,
        )
        if r.status_code == 200:
            return r.text.strip()
    except Exception:
        pass
    return os.environ.get("SENTINEL_MODE", "baseline")


def main() -> None:
    setup_logging() if "setup_logging" in globals() else None

    project_id = os.environ["GCP_PROJECT_ID"]
    raw_topic = os.environ.get("PUBSUB_TOPIC", os.environ.get("PUBSUB_RAW_TOPIC", "sentinel-dev-raw-traffic"))
    tel_topic = os.environ.get("PUBSUB_TELEMETRY_TOPIC", "sentinel-dev-telemetry")
    endpoint_id = os.environ.get("ENDPOINT_FULL", "victim-recommender")

    pub = Publisher(project_id) if "Publisher" in globals() else None
    # Fallback raw client if utils not on path:
    if pub is None:
        from google.cloud import pubsub_v1
        client = pubsub_v1.PublisherClient()
        raw_path = client.topic_path(project_id, raw_topic)
        tel_path = client.topic_path(project_id, tel_topic)
        def publish(topic_path, payload):
            import json
            client.publish(topic_path, json.dumps(payload, default=str).encode()).result(timeout=10)
    else:
        def publish(topic, payload):
            target = raw_topic if topic == "raw" else tel_topic
            pub.publish_json(target, payload)

    log.info("traffic_generator starting", extra={"project": project_id, "raw_topic": raw_topic})

    last_mode = None
    while True:
        mode = read_mode_from_metadata()
        if mode != last_mode:
            log.info("mode change", extra={"event": "mode_change", "old": last_mode, "new": mode})
            last_mode = mode

        if mode == "off":
            time.sleep(5)
            continue

        gen = get_generator(mode)
        sample = gen()
        if sample is None:
            time.sleep(5)
            continue

        request_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc).isoformat()

        # Publish raw event to raw-traffic topic
        raw_event = {
            "request_id": request_id,
            "user_id": sample.user_id,
            "review_text": sample.review_text,
            "event_time": now,
        }
        if pub is None:
            publish(raw_path, raw_event)
        else:
            publish("raw", raw_event)

        # Also publish per-metric telemetry (this is what the forecaster
        # ultimately learns from — feature_logger does this in production
        # but we shortcut here for synthetic load).
        for metric_name, value in [
            ("latency_ms", sample.request_latency_ms),
            ("image_embedding_norm", sample.image_embedding_norm),
            ("review_token_count", float(sample.review_token_count)),
            ("error_rate", 1.0 if sample.error else 0.0),
        ]:
            tel_event = {
                "event_time": now,
                "endpoint_id": endpoint_id,
                "metric_name": metric_name,
                "metric_value": float(value),
                "request_id": request_id,
                "feature_stats": {"mode": mode},
            }
            if pub is None:
                publish(tel_path, tel_event)
            else:
                publish("telemetry", tel_event)

        time.sleep(sleep_between(mode))


if __name__ == "__main__":
    main()
