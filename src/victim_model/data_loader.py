"""
============================================================
WHAT  : Loads/synthesizes a small product+review dataset.
WHY   : For the demo we don't need a real Amazon dataset —
        a synthetic one keeps storage costs at $0 and lets
        anyone reproduce the project with no permissions.
HOW   : Generates N synthetic products with random reviews
        and random images (uniform noise — embeddings still
        project to a usable manifold for demo purposes).
============================================================
"""
from __future__ import annotations

import logging
import random
from dataclasses import dataclass
from pathlib import Path

import numpy as np

log = logging.getLogger(__name__)


@dataclass
class Product:
    product_id: str
    title: str
    review_text: str
    image: np.ndarray  # (H, W, 3) uint8


_TITLE_PARTS = ["Sport", "Trail", "Urban", "Classic", "Pro", "Lite"]
_TITLE_TYPES = ["Runner", "Sneaker", "Boot", "Sandal", "Cross-trainer"]
_REVIEW_TEMPLATES = [
    "Loved these {t}; comfortable for daily wear.",
    "{t} are stylish but run a bit small.",
    "Great support and grip on these {t}.",
    "Decent {t} for the price.",
    "Disappointed with the {t} after one wash.",
]


def synth_dataset(n: int = 200, img_size: int = 64, seed: int = 0) -> list[Product]:
    """Returns a list of N synthetic products (cheap & deterministic)."""
    rng = random.Random(seed)
    np_rng = np.random.RandomState(seed)
    products: list[Product] = []
    for i in range(n):
        type_ = rng.choice(_TITLE_TYPES)
        title = f"{rng.choice(_TITLE_PARTS)} {type_} #{i:03d}"
        review = rng.choice(_REVIEW_TEMPLATES).format(t=type_.lower() + "s")
        image = (np_rng.rand(img_size, img_size, 3) * 255).astype(np.uint8)
        products.append(Product(product_id=f"p{i:04d}", title=title, review_text=review, image=image))
    log.info("synth dataset", extra={"n": n})
    return products


def save_to_disk(products: list[Product], path: str | Path) -> None:
    """Persist as a numpy archive for fast reload (used by training)."""
    path = Path(path)
    path.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(
        path / "products.npz",
        ids=np.array([p.product_id for p in products]),
        titles=np.array([p.title for p in products]),
        reviews=np.array([p.review_text for p in products]),
        images=np.stack([p.image for p in products]),
    )
