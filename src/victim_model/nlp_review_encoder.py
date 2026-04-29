"""
============================================================
WHAT  : NLP review text encoder using a small DistilBERT.
WHY   : AI #1 needs to embed product reviews into a dense
        vector that can be combined with image features.
HOW   : HuggingFace transformers DistilBERT (no fine-tuning;
        we use it frozen — training the two-tower head only).
LAYMAN: Turns "great running shoes!" into a 384-dim vector
        the recommender can compare to other reviews.
JD KEYWORD: NLP, PyTorch, transformers
============================================================
"""
from __future__ import annotations

import logging

import torch

log = logging.getLogger(__name__)


class ReviewEncoder:
    """Wraps a frozen DistilBERT for review text embeddings."""

    EMBED_DIM = 768  # DistilBERT hidden size

    def __init__(self, model_name: str = "distilbert-base-uncased", device: str | None = None):
        # Lazy import so this module is import-cheap on machines without torch.
        from transformers import AutoModel, AutoTokenizer

        self.device = device or ("cuda" if torch.cuda.is_available() else "cpu")
        log.info("loading review encoder", extra={"model": model_name, "device": self.device})
        self.tokenizer = AutoTokenizer.from_pretrained(model_name)
        self.model = AutoModel.from_pretrained(model_name).to(self.device)
        self.model.eval()
        for p in self.model.parameters():
            p.requires_grad = False

    @torch.no_grad()
    def encode(self, texts: list[str], max_length: int = 64) -> torch.Tensor:
        """Return mean-pooled embeddings of shape (batch, EMBED_DIM)."""
        if not texts:
            return torch.zeros(0, self.EMBED_DIM)
        enc = self.tokenizer(
            texts,
            padding=True,
            truncation=True,
            max_length=max_length,
            return_tensors="pt",
        ).to(self.device)
        out = self.model(**enc).last_hidden_state  # (B, T, H)

        # Mean-pool over non-padding tokens
        mask = enc["attention_mask"].unsqueeze(-1).float()
        pooled = (out * mask).sum(dim=1) / mask.sum(dim=1).clamp(min=1)
        return pooled.cpu()
