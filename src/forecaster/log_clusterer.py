"""
============================================================
WHAT  : NLP module — clusters Cloud Logging error messages
        into groups so we spot new failure modes fast.
WHY   : When a wave of errors hits, you don't want 1000
        identical lines — you want "5 distinct error types
        this hour, here are exemplars".
HOW   : Sentence embeddings (DistilBERT) -> KMeans clusters
        -> exemplar message per cluster.
LAYMAN: Group similar log lines so a human reads 5 instead
        of 5000.
JD KEYWORD: NLP, log analysis (TSE bread-and-butter)
============================================================
"""
from __future__ import annotations

import logging
from dataclasses import dataclass

import numpy as np
from sklearn.cluster import KMeans

from src.victim_model.nlp_review_encoder import ReviewEncoder

log = logging.getLogger(__name__)


@dataclass
class LogCluster:
    cluster_id: int
    size: int
    exemplar: str
    samples: list[str]


class LogClusterer:
    """Re-uses the DistilBERT encoder for log messages."""

    def __init__(self, max_clusters: int = 5):
        self.encoder = ReviewEncoder()
        self.max_clusters = max_clusters

    def cluster(self, messages: list[str]) -> list[LogCluster]:
        if not messages:
            return []
        # Limit for cost (we only need a few seconds of recent logs)
        messages = messages[-500:]

        embs = self.encoder.encode(messages, max_length=64).numpy()
        k = min(self.max_clusters, len(messages))
        if k <= 1:
            return [LogCluster(0, len(messages), messages[0], messages[:5])]

        km = KMeans(n_clusters=k, n_init=5, random_state=0)
        labels = km.fit_predict(embs)

        clusters: list[LogCluster] = []
        for cid in range(k):
            idxs = np.where(labels == cid)[0]
            if len(idxs) == 0:
                continue
            # Exemplar = closest to the centroid
            center = km.cluster_centers_[cid]
            dists = np.linalg.norm(embs[idxs] - center, axis=1)
            exemplar_idx = idxs[int(np.argmin(dists))]
            clusters.append(LogCluster(
                cluster_id=cid,
                size=len(idxs),
                exemplar=messages[exemplar_idx],
                samples=[messages[i] for i in idxs[:5]],
            ))
        clusters.sort(key=lambda c: c.size, reverse=True)
        return clusters
