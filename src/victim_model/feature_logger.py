"""
============================================================
WHAT  : On every prediction, publish per-feature stats to
        Pub/Sub `telemetry` so the forecaster can monitor.
WHY   : Vertex AI Model Monitoring catches drift AT the
        threshold. We want to forecast it BEFORE — so we
        emit our own continuous feature statistics.
HOW   : Lightweight: just publish the norm of the input
        embeddings + the request latency.
LAYMAN: After every shoe recommendation, write down
        "the input photo had this brightness, the answer
        took this long" so the doctor (AI #2) can watch.
============================================================
"""
from __future__ import annotations

import logging
import time
from datetime import datetime, timezone

from src.utils.config import get_config
from src.utils.pubsub_client import Publisher

log = logging.getLogger(__name__)


class FeatureLogger:
    def __init__(self):
        cfg = get_config()
        self.cfg = cfg
        self.pub = Publisher(cfg.project_id)

    def log(
        self,
        request_id: str,
        endpoint_id: str,
        latency_ms: float,
        text_emb_norm: float,
        image_emb_norm: float,
        review_token_count: int,
        error: bool = False,
    ) -> None:
        now = datetime.now(timezone.utc).isoformat()
        rows = [
            {"event_time": now, "endpoint_id": endpoint_id, "metric_name": "latency_ms",
             "metric_value": float(latency_ms), "request_id": request_id},
            {"event_time": now, "endpoint_id": endpoint_id, "metric_name": "text_emb_norm",
             "metric_value": float(text_emb_norm), "request_id": request_id},
            {"event_time": now, "endpoint_id": endpoint_id, "metric_name": "image_embedding_norm",
             "metric_value": float(image_emb_norm), "request_id": request_id},
            {"event_time": now, "endpoint_id": endpoint_id, "metric_name": "review_token_count",
             "metric_value": float(review_token_count), "request_id": request_id},
            {"event_time": now, "endpoint_id": endpoint_id, "metric_name": "error_rate",
             "metric_value": 1.0 if error else 0.0, "request_id": request_id},
        ]
        for r in rows:
            try:
                self.pub.publish_json(self.cfg.topic_telemetry, r)
            except Exception:
                log.exception("feature publish failed; continuing")
