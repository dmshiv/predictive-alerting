"""
============================================================
WHAT  : Computer-vision image encoder using a small CNN.
WHY   : AI #1 needs to embed product photos. Combined with
        the review encoder, this gives a true multi-modal
        recommender.
HOW   : MobileNetV3 from TF/Keras (small, fast, free of
        license worries). Frozen — used as a feature extractor.
LAYMAN: Turns a product photo into a 1024-dim vector.
JD KEYWORD: Computer Vision, TensorFlow / Keras
============================================================
"""
from __future__ import annotations

import logging

import numpy as np

log = logging.getLogger(__name__)


class ImageEncoder:
    """Wraps a frozen MobileNetV3 (small) for image embeddings."""

    EMBED_DIM = 1024  # MobileNetV3-Small global-pool dim

    def __init__(self):
        # Lazy import; TF is heavy.
        import tensorflow as tf
        from tensorflow.keras.applications import MobileNetV3Small

        self.tf = tf
        log.info("loading image encoder", extra={"model": "MobileNetV3Small"})

        base = MobileNetV3Small(
            weights="imagenet",
            include_top=False,
            pooling="avg",
        )
        base.trainable = False
        self.model = base

    def preprocess(self, img_array: np.ndarray) -> np.ndarray:
        """img_array: HxWx3 uint8 -> resized + normalized for MobileNetV3."""
        from tensorflow.keras.applications.mobilenet_v3 import preprocess_input

        img = self.tf.image.resize(img_array, [224, 224])
        return preprocess_input(self.tf.cast(img, self.tf.float32))

    def encode(self, batch_imgs: np.ndarray) -> np.ndarray:
        """batch_imgs: (B, H, W, 3) -> (B, EMBED_DIM)."""
        if len(batch_imgs) == 0:
            return np.zeros((0, self.EMBED_DIM), dtype=np.float32)
        x = self.tf.stack([self.preprocess(im) for im in batch_imgs])
        embs = self.model(x, training=False).numpy()
        return embs
