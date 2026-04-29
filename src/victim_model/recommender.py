"""
============================================================
WHAT  : Two-tower recommender that fuses NLP + CV embeddings
        and produces a top-K product recommendation.
WHY   : AI #1 = the patient — must look like a "real-world"
        ML model the doctor (AI #2) watches.
HOW   : Query tower    : concat(user_review_emb, user_image_emb) -> dense
        Candidate tower: concat(product_review_emb, product_image_emb) -> dense
        Score          : dot(query, candidate)
LAYMAN: Imagine two towers shaking hands — query tower
        (the user) and candidate tower (each shoe). They
        produce vectors, we measure handshake strength.
JD KEYWORD: RecSys, two-tower retrieval
============================================================
"""
from __future__ import annotations

import logging
from dataclasses import dataclass

import numpy as np
import torch
import torch.nn as nn

log = logging.getLogger(__name__)


@dataclass
class TowerConfig:
    text_dim: int = 768          # ReviewEncoder.EMBED_DIM
    image_dim: int = 1024        # ImageEncoder.EMBED_DIM
    hidden: int = 512
    output: int = 256


class _Tower(nn.Module):
    def __init__(self, cfg: TowerConfig):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(cfg.text_dim + cfg.image_dim, cfg.hidden),
            nn.ReLU(),
            nn.Linear(cfg.hidden, cfg.output),
        )

    def forward(self, text_emb: torch.Tensor, image_emb: torch.Tensor) -> torch.Tensor:
        x = torch.cat([text_emb, image_emb], dim=-1)
        return torch.nn.functional.normalize(self.net(x), dim=-1)


class TwoTowerRecommender(nn.Module):
    """The full multi-modal recommender model."""

    def __init__(self, cfg: TowerConfig | None = None):
        super().__init__()
        cfg = cfg or TowerConfig()
        self.cfg = cfg
        self.query_tower = _Tower(cfg)
        self.candidate_tower = _Tower(cfg)

    def encode_query(self, text_emb, image_emb) -> torch.Tensor:
        return self.query_tower(text_emb, image_emb)

    def encode_candidate(self, text_emb, image_emb) -> torch.Tensor:
        return self.candidate_tower(text_emb, image_emb)

    def score(self, query_text, query_image, cand_text, cand_image) -> torch.Tensor:
        """Returns an (Nq, Nc) similarity matrix."""
        q = self.encode_query(query_text, query_image)
        c = self.encode_candidate(cand_text, cand_image)
        return q @ c.t()

    def top_k(
        self,
        query_text: torch.Tensor,
        query_image: torch.Tensor,
        cand_text: torch.Tensor,
        cand_image: torch.Tensor,
        k: int = 5,
    ) -> tuple[np.ndarray, np.ndarray]:
        """Returns (indices, scores) of shape (Nq, k)."""
        with torch.no_grad():
            scores = self.score(query_text, query_image, cand_text, cand_image)
            topk = scores.topk(min(k, scores.size(1)), dim=-1)
        return topk.indices.cpu().numpy(), topk.values.cpu().numpy()
