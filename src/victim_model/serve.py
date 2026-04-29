"""
============================================================
WHAT  : FastAPI serving wrapper around the two-tower model.
        Containerized via docker/victim.Dockerfile and deployed
        to Vertex AI Endpoint #1 (or run on GKE for local-ish).
WHY   : Vertex AI Endpoints needs a /predict-style HTTP server.
HOW   : Loads model artifact from GCS at startup; on each
        request encodes input review+image, scores against
        the cached candidate index, returns top-K + emits
        feature telemetry.
============================================================
"""
from __future__ import annotations

import logging
import os
import time
from contextlib import asynccontextmanager

import numpy as np
import torch
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from src.utils.config import get_config
from src.utils.gcs_client import GCS
from src.utils.logging_config import setup_logging
from src.victim_model.feature_logger import FeatureLogger
from src.victim_model.recommender import TowerConfig, TwoTowerRecommender

log = logging.getLogger(__name__)
setup_logging()

# --- Model state (populated at startup) -------------------------------------
_state: dict = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    cfg = get_config()
    gcs = GCS(cfg.project_id)
    local = "/tmp/victim_model.pt"
    log.info("loading model from GCS", extra={"bucket": cfg.bucket_models})
    try:
        gcs.download_file(cfg.bucket_models, "victim/victim_model.pt", local)
    except Exception:
        log.warning("could not load model from GCS; serving in 'echo' mode")
        _state["echo"] = True
        yield
        return

    artefact = torch.load(local, map_location="cpu", weights_only=False)
    cfg_t = TowerConfig(**artefact["tower_config"])
    model = TwoTowerRecommender(cfg_t)
    model.load_state_dict(artefact["model_state"])
    model.eval()

    # Pre-encode candidate side once
    cand_text = torch.from_numpy(artefact["review_emb"])
    cand_image = torch.from_numpy(artefact["image_emb"])
    with torch.no_grad():
        cand_vecs = model.candidate_tower(cand_text, cand_image)

    _state.update({
        "model": model,
        "cand_vecs": cand_vecs,
        "ids": artefact["product_ids"],
        "titles": artefact["product_titles"],
        "feature_logger": FeatureLogger(),
        "endpoint_id": os.environ.get("VERTEX_ENDPOINT_ID", "victim-recommender"),
        "echo": False,
    })
    log.info("model ready", extra={"n_candidates": len(_state["ids"])})
    yield
    _state.clear()


app = FastAPI(lifespan=lifespan)


class PredictRequest(BaseModel):
    instances: list[dict]   # Vertex AI convention: [{"review_text": "...", "image_norm": 0.92}, ...]


class PredictResponse(BaseModel):
    predictions: list[list[dict]]


@app.get("/healthz")
def healthz():
    return {"ok": True, "ready": "model" in _state or _state.get("echo", False)}


@app.post("/predict", response_model=PredictResponse)
def predict(req: PredictRequest) -> PredictResponse:
    t0 = time.time()
    if _state.get("echo"):
        # Fallback when model not yet loaded
        return PredictResponse(predictions=[
            [{"product_id": "p0000", "title": "fallback", "score": 0.0}] for _ in req.instances
        ])

    model: TwoTowerRecommender = _state["model"]
    cand_vecs: torch.Tensor = _state["cand_vecs"]
    ids = _state["ids"]
    titles = _state["titles"]
    fl: FeatureLogger = _state["feature_logger"]

    # For demo simplicity: synthesize a query embedding from the input "image_norm".
    # In a real system, this would call ReviewEncoder + ImageEncoder.
    out: list[list[dict]] = []
    for inst in req.instances:
        image_norm = float(inst.get("image_norm", 1.0))
        text_norm = float(inst.get("text_norm", 1.0))
        token_count = int(inst.get("review_token_count", 20))

        # Cheap synthetic query — keeps serving fast and demo-able
        q = torch.randn(1, model.cfg.output) * image_norm
        q = torch.nn.functional.normalize(q, dim=-1)
        scores = q @ cand_vecs.t()
        topk = scores.topk(min(5, scores.size(1)), dim=-1)

        recs = [
            {"product_id": ids[i], "title": titles[i], "score": float(s)}
            for i, s in zip(topk.indices[0].tolist(), topk.values[0].tolist())
        ]
        out.append(recs)

        # Emit telemetry (fire-and-forget)
        latency = (time.time() - t0) * 1000
        try:
            fl.log(
                request_id=inst.get("request_id", "unknown"),
                endpoint_id=_state["endpoint_id"],
                latency_ms=latency,
                text_emb_norm=text_norm,
                image_emb_norm=image_norm,
                review_token_count=token_count,
                error=False,
            )
        except Exception:
            log.exception("telemetry publish failed")

    return PredictResponse(predictions=out)
