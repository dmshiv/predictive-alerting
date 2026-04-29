"""
============================================================
WHAT  : Thin BigQuery helper with retries.
WHY   : Most code just wants "insert these rows" or "give me
        the last N minutes of telemetry" — without the SDK
        boilerplate everywhere.
HOW   : Wraps google.cloud.bigquery.Client with tenacity
        retries.
LAYMAN: A friendly front-desk for the BigQuery warehouse.
============================================================
"""
from __future__ import annotations

import logging
from typing import Iterable

from google.cloud import bigquery
from tenacity import retry, stop_after_attempt, wait_exponential

log = logging.getLogger(__name__)


class BQ:
    def __init__(self, project_id: str):
        self.client = bigquery.Client(project=project_id)
        self.project_id = project_id

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(min=1, max=10))
    def insert_rows(self, table_fqn: str, rows: Iterable[dict]) -> None:
        """Streaming insert. table_fqn = 'project.dataset.table'."""
        rows = list(rows)
        if not rows:
            return
        errors = self.client.insert_rows_json(table_fqn, rows)
        if errors:
            log.error("BQ insert errors", extra={"errors": str(errors)[:500]})
            raise RuntimeError(f"BQ insert errors: {errors}")
        log.debug("BQ inserted", extra={"table": table_fqn, "n_rows": len(rows)})

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(min=1, max=10))
    def query(self, sql: str) -> list[dict]:
        """Run a SQL query and return list of dict rows."""
        result = self.client.query(sql).result()
        return [dict(row) for row in result]

    def query_df(self, sql: str):
        """Run a SQL query and return a pandas DataFrame."""
        return self.client.query(sql).to_dataframe()
