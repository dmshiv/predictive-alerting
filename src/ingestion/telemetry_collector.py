"""
============================================================
WHAT  : Pulls events from the Pub/Sub `telemetry` topic and
        streams them into BigQuery `telemetry_raw`.
WHY   : So we have a queryable history of every metric for
        the forecaster to train on and the dashboard to read.
HOW   : Streaming pull subscription -> batched insert_rows.
        Runs as a single GKE pod with WI auth.
LAYMAN: The "data plumber" — moves measurements from the
        message queue into the warehouse.
============================================================
"""
from __future__ import annotations

import json
import logging
import os
import signal
import threading
import time
from datetime import datetime, timezone

from src.utils.bq_client import BQ
from src.utils.config import get_config
from src.utils.logging_config import setup_logging
from src.utils.pubsub_client import Subscriber

log = logging.getLogger(__name__)

# In-memory buffer for batching BQ inserts (1000 rows or 5s, whichever first)
_BUFFER: list[dict] = []
_BUFFER_LOCK = threading.Lock()
_BUFFER_MAX = 1000
_BUFFER_FLUSH_SEC = 5
_STOP = threading.Event()


def _flusher(bq: BQ, table_fqn: str) -> None:
    """Background thread: flushes buffer every _BUFFER_FLUSH_SEC."""
    while not _STOP.is_set():
        time.sleep(_BUFFER_FLUSH_SEC)
        _flush(bq, table_fqn)


def _flush(bq: BQ, table_fqn: str) -> None:
    with _BUFFER_LOCK:
        if not _BUFFER:
            return
        rows, _BUFFER[:] = list(_BUFFER), []
    try:
        bq.insert_rows(table_fqn, rows)
        log.info("flushed to BQ", extra={"event": "bq_flush", "n_rows": len(rows), "table": table_fqn})
    except Exception:
        log.exception("BQ flush failed; dropping batch")


def main() -> None:
    setup_logging()
    cfg = get_config()
    bq = BQ(cfg.project_id)
    sub = Subscriber(cfg.project_id)

    table_fqn = cfg.bq_telemetry_table
    subscription = os.environ.get(
        "PUBSUB_SUBSCRIPTION",
        f"{cfg.name_prefix}-ingestion-telemetry",
    )

    log.info("telemetry collector starting",
             extra={"subscription": subscription, "table": table_fqn})

    # Start the flusher thread
    threading.Thread(target=_flusher, args=(bq, table_fqn), daemon=True).start()

    def on_message(payload: dict, msg) -> None:
        # Coerce types so BQ accepts the row.
        # NOTE: `feature_stats` is a BQ JSON column; insert_rows_json requires
        # a JSON-encoded string (NOT a python dict, which BQ would interpret
        # as a STRUCT/record and reject with "is not a record").
        fs = payload.get("feature_stats")
        if fs is not None and not isinstance(fs, str):
            fs = json.dumps(fs, default=str)
        row = {
            "event_time": payload.get("event_time") or datetime.now(timezone.utc).isoformat(),
            "endpoint_id": str(payload.get("endpoint_id", "")),
            "metric_name": str(payload.get("metric_name", "")),
            "metric_value": float(payload.get("metric_value", 0.0)),
            "request_id": payload.get("request_id"),
            "feature_stats": fs,
        }
        with _BUFFER_LOCK:
            _BUFFER.append(row)
            if len(_BUFFER) >= _BUFFER_MAX:
                rows, _BUFFER[:] = list(_BUFFER), []
            else:
                rows = None
        if rows is not None:
            try:
                bq.insert_rows(table_fqn, rows)
            except Exception:
                log.exception("inline flush failed")
        msg.ack()

    future = sub.subscribe(subscription, on_message)

    # Graceful shutdown
    def _shutdown(*_):
        log.info("shutting down")
        _STOP.set()
        try:
            future.cancel()
        except Exception:
            pass
        _flush(bq, table_fqn)
        os._exit(0)

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    try:
        future.result()
    except KeyboardInterrupt:
        _shutdown()


if __name__ == "__main__":
    main()
