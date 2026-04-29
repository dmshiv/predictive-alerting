"""
============================================================
WHAT  : Cloud Storage helper for upload/download/listing.
WHY   : Models, training data, and TensorBoard logs all live
        in GCS; a thin wrapper avoids SDK noise.
============================================================
"""
from __future__ import annotations

import io
import logging
from pathlib import Path

from google.cloud import storage

log = logging.getLogger(__name__)


class GCS:
    def __init__(self, project_id: str):
        self.client = storage.Client(project=project_id)
        self.project_id = project_id

    def upload_file(self, bucket: str, src: str | Path, dst: str) -> str:
        b = self.client.bucket(bucket)
        blob = b.blob(dst)
        blob.upload_from_filename(str(src))
        log.info("uploaded", extra={"bucket": bucket, "src": str(src), "dst": dst})
        return f"gs://{bucket}/{dst}"

    def upload_bytes(self, bucket: str, data: bytes, dst: str, content_type: str = "application/octet-stream") -> str:
        b = self.client.bucket(bucket)
        blob = b.blob(dst)
        blob.upload_from_string(data, content_type=content_type)
        return f"gs://{bucket}/{dst}"

    def download_file(self, bucket: str, src: str, dst: str | Path) -> None:
        b = self.client.bucket(bucket)
        b.blob(src).download_to_filename(str(dst))

    def download_bytes(self, bucket: str, src: str) -> bytes:
        b = self.client.bucket(bucket)
        return b.blob(src).download_as_bytes()

    def exists(self, bucket: str, path: str) -> bool:
        return self.client.bucket(bucket).blob(path).exists()

    def list_prefix(self, bucket: str, prefix: str) -> list[str]:
        return [b.name for b in self.client.list_blobs(bucket, prefix=prefix)]
