"""
============================================================
WHAT  : Trains the two-tower victim recommender.
WHY   : So the live endpoint serves something that responds
        and produces signal we can actually monitor.
HOW   : 1. Generate synthetic products
        2. Encode reviews (DistilBERT) + images (MobileNetV3)
        3. Train two-tower with sampled-softmax loss
        4. Save the model artifact + index to GCS
LAYMAN: Teach two AIs (text reader + image looker) to agree
        on which products go together, then save the trained
        agreement so the live API can serve recommendations.
============================================================
"""
from __future__ import annotations

import argparse
import logging
import os
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import DataLoader, TensorDataset

from src.utils.config import get_config
from src.utils.gcs_client import GCS
from src.utils.logging_config import setup_logging
from src.victim_model.data_loader import synth_dataset
from src.victim_model.nlp_review_encoder import ReviewEncoder
from src.victim_model.recommender import TowerConfig, TwoTowerRecommender
from src.victim_model.vision_image_encoder import ImageEncoder

log = logging.getLogger(__name__)


def train_one_epoch(model: TwoTowerRecommender, loader: DataLoader, optim: torch.optim.Optimizer) -> float:
    """Sampled-softmax: each batch's products are negatives for each other."""
    model.train()
    total_loss = 0.0
    n = 0
    for text_emb, image_emb in loader:
        # In this synthetic demo, query == candidate (trivially solvable);
        # we add small noise to make the task non-trivial.
        q_text = text_emb + torch.randn_like(text_emb) * 0.05
        q_image = image_emb + torch.randn_like(image_emb) * 0.05

        scores = model.score(q_text, q_image, text_emb, image_emb)  # (B, B)
        labels = torch.arange(scores.size(0), device=scores.device)
        loss = torch.nn.functional.cross_entropy(scores, labels)

        optim.zero_grad()
        loss.backward()
        optim.step()

        total_loss += loss.item() * scores.size(0)
        n += scores.size(0)
    return total_loss / max(1, n)


def main() -> None:
    setup_logging()
    parser = argparse.ArgumentParser()
    parser.add_argument("--n-products", type=int, default=200)
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--out-dir", type=str, default="/tmp/sentinel_victim")
    parser.add_argument("--upload-to-gcs", action="store_true")
    args = parser.parse_args()

    cfg = get_config()
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    # 1. Data
    products = synth_dataset(args.n_products)

    # 2. Encode
    log.info("encoding reviews + images (one-shot)")
    review_enc = ReviewEncoder()
    image_enc = ImageEncoder()

    review_emb = review_enc.encode([p.review_text for p in products])
    image_arr = np.stack([p.image for p in products])
    image_emb = torch.from_numpy(image_enc.encode(image_arr))

    # 3. Train
    cfg_t = TowerConfig(text_dim=ReviewEncoder.EMBED_DIM, image_dim=ImageEncoder.EMBED_DIM)
    model = TwoTowerRecommender(cfg_t)
    optim = torch.optim.Adam(model.parameters(), lr=args.lr)
    ds = TensorDataset(review_emb, image_emb)
    loader = DataLoader(ds, batch_size=args.batch_size, shuffle=True)

    for epoch in range(args.epochs):
        loss = train_one_epoch(model, loader, optim)
        log.info("epoch done", extra={"event": "train_epoch", "epoch": epoch, "loss": loss})

    # 4. Save artifacts
    artefact = {
        "model_state": model.state_dict(),
        "tower_config": cfg_t.__dict__,
        "review_emb": review_emb.numpy(),
        "image_emb": image_emb.numpy(),
        "product_ids": [p.product_id for p in products],
        "product_titles": [p.title for p in products],
    }
    model_path = out / "victim_model.pt"
    torch.save(artefact, model_path)
    log.info("saved model", extra={"path": str(model_path)})

    if args.upload_to_gcs:
        gcs = GCS(cfg.project_id)
        url = gcs.upload_file(cfg.bucket_models, model_path, "victim/victim_model.pt")
        log.info("uploaded to GCS", extra={"url": url})


if __name__ == "__main__":
    main()
