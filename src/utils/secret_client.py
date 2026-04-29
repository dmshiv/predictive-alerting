"""
============================================================
WHAT  : Secret Manager helper with in-process caching.
WHY   : Triage service reads Gemini API key on every alert;
        no point re-fetching it from Secret Manager 100x/min.
HOW   : Cache by secret_id; refresh manually if needed.
============================================================
"""
from __future__ import annotations

import logging

from google.cloud import secretmanager

log = logging.getLogger(__name__)


class Secrets:
    def __init__(self, project_id: str):
        self.client = secretmanager.SecretManagerServiceClient()
        self.project_id = project_id
        self._cache: dict[str, str] = {}

    def get(self, secret_id: str, version: str = "latest", refresh: bool = False) -> str:
        """Return the secret value as a string. Caches by secret_id."""
        if not refresh and secret_id in self._cache:
            return self._cache[secret_id]

        name = f"projects/{self.project_id}/secrets/{secret_id}/versions/{version}"
        try:
            response = self.client.access_secret_version(request={"name": name})
            value = response.payload.data.decode("utf-8")
            self._cache[secret_id] = value
            return value
        except Exception as e:
            log.warning("secret not accessible; returning empty", extra={"secret": secret_id, "err": str(e)})
            return ""
