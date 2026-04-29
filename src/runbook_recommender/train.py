"""
============================================================
WHAT  : Trains the runbook recommender on historical incidents.
WHY   : So matching gets better as we collect more data.
HOW   : Reads `incidents` + `runbook_history` from BigQuery,
        learns which runbook tags worked best per incident
        signature, persists scores to a JSON the recommender
        loads at boot.
NOTE  : For the demo, this is mostly a stub — the rule-based
        recommender already works. This trainer kicks in once
        you have >50 historical incidents.
============================================================
"""
from __future__ import annotations

import argparse
import json
import logging
from collections import Counter, defaultdict
from pathlib import Path

from src.utils.bq_client import BQ
from src.utils.config import get_config
from src.utils.gcs_client import GCS
from src.utils.logging_config import setup_logging

log = logging.getLogger(__name__)


def main() -> None:
    setup_logging()
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-path", default="/tmp/runbook_scores.json")
    parser.add_argument("--upload-to-gcs", action="store_true")
    args = parser.parse_args()

    cfg = get_config()
    bq = BQ(cfg.project_id)

    # Pull joined history
    sql = f"""
      SELECT i.metric_name, i.severity, h.runbook_id, h.success
      FROM `{cfg.bq_incidents_table}` i
      JOIN `{cfg.project_id}.{cfg.bq_dataset_incidents}.runbook_history` h
        USING (incident_id)
    """
    try:
        rows = bq.query(sql)
    except Exception:
        log.exception("query failed; possibly no incidents yet")
        rows = []

    # Tally success counts per (signature, runbook_id)
    counts: dict[tuple[str, str], Counter] = defaultdict(Counter)
    for r in rows:
        key = (r["metric_name"], r["severity"])
        counts[key][r["runbook_id"]] += 1 if r["success"] else 0

    scores: dict[str, dict[str, float]] = {}
    for (metric, sev), c in counts.items():
        total = max(1, sum(c.values()))
        scores[f"{metric}|{sev}"] = {rb: v / total for rb, v in c.items()}

    Path(args.out_path).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out_path).write_text(json.dumps(scores, indent=2))
    log.info("scores written", extra={"path": args.out_path, "n_signatures": len(scores)})

    if args.upload_to_gcs:
        gcs = GCS(cfg.project_id)
        gcs.upload_file(cfg.bucket_models, args.out_path, "runbook_recommender/scores.json")


if __name__ == "__main__":
    main()
