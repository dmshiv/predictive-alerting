"""
============================================================
WHAT  : KFP component — trains the victim recommender (AI #1).
WHY   : Pipeline stage so we can rerun + version this nightly.
HOW   : Wraps src/victim_model/train.py.
============================================================
"""
from __future__ import annotations

from kfp import dsl


@dsl.component(
    base_image="python:3.11-slim",
    packages_to_install=[
        "torch==2.4.1",
        "tensorflow==2.17.0",
        "transformers==4.45.0",
        "google-cloud-storage==2.18.0",
        "numpy==1.26.4",
    ],
)
def train_victim_op(project_id: str, env_name: str, output_uri: str, n_products: int = 200) -> str:
    """Train + save the two-tower model. Synthetic data so it always works."""
    import logging
    import numpy as np
    import torch
    from torch import nn
    from google.cloud import storage

    logging.basicConfig(level="INFO")
    log = logging.getLogger("train_victim_op")

    # Synthetic embeddings (real model uses DistilBERT + MobileNetV3 — heavy for KFP)
    rng = np.random.default_rng(0)
    text_emb = torch.from_numpy(rng.standard_normal((n_products, 768)).astype("float32"))
    image_emb = torch.from_numpy(rng.standard_normal((n_products, 1024)).astype("float32"))

    # Tiny two-tower
    class Tower(nn.Module):
        def __init__(self, td=768, im=1024, h=512, o=256):
            super().__init__()
            self.net = nn.Sequential(nn.Linear(td+im, h), nn.ReLU(), nn.Linear(h, o))
        def forward(self, t, i):
            return torch.nn.functional.normalize(self.net(torch.cat([t, i], dim=-1)), dim=-1)

    qt = Tower(); ct = Tower()
    opt = torch.optim.Adam(list(qt.parameters()) + list(ct.parameters()), lr=1e-3)
    for epoch in range(3):
        idx = torch.randperm(n_products)[:64]
        q = qt(text_emb[idx] + 0.05*torch.randn_like(text_emb[idx]),
               image_emb[idx] + 0.05*torch.randn_like(image_emb[idx]))
        c = ct(text_emb[idx], image_emb[idx])
        scores = q @ c.t()
        loss = torch.nn.functional.cross_entropy(scores, torch.arange(scores.size(0)))
        opt.zero_grad(); loss.backward(); opt.step()
        log.info("epoch %d loss=%.4f", epoch, loss.item())

    # Save
    artefact = {
        "model_state": {**{f"q.{k}": v for k,v in qt.state_dict().items()},
                        **{f"c.{k}": v for k,v in ct.state_dict().items()}},
        "tower_config": {"text_dim": 768, "image_dim": 1024, "hidden": 512, "output": 256},
        "review_emb": text_emb.numpy(),
        "image_emb": image_emb.numpy(),
        "product_ids": [f"p{i:04d}" for i in range(n_products)],
        "product_titles": [f"Product {i}" for i in range(n_products)],
    }
    torch.save(artefact, "/tmp/victim_model.pt")

    if output_uri.startswith("gs://"):
        bucket, _, key = output_uri.replace("gs://", "").partition("/")
        client = storage.Client(project=project_id)
        client.bucket(bucket).blob(f"{key}/victim_model.pt").upload_from_filename("/tmp/victim_model.pt")
        return f"gs://{bucket}/{key}/victim_model.pt"
    return "/tmp/victim_model.pt"
