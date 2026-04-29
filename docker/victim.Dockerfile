# =============================================================================
# WHAT  : Container for AI #1 (multi-modal recommender) served on Vertex / GKE.
# WHY   : Wraps DistilBERT + a CV stub behind a FastAPI HTTP endpoint so the
#         load generator can hammer it with /recommend requests.
# HOW   : Slim Python base + CPU-only torch + transformers + uvicorn server.
# LAYMAN: This is the "store clerk" robot. Customers (load-gen) ask "what
#         should I buy?" and this robot answers with a recommendation.
# =============================================================================

# --- 1. Base image -----------------------------------------------------------
# python:3.11-slim is ~50MB vs 900MB for the full image. Keeps things lean.
FROM python:3.11-slim

# --- 2. Python runtime tweaks ------------------------------------------------
# PYTHONUNBUFFERED=1   -> logs flush immediately so you see them in real time
# PIP_NO_CACHE_DIR=1   -> don't keep pip's cache; saves ~200MB in the image
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1

# --- 3. OS-level deps --------------------------------------------------------
# torch needs libgomp1 for OpenMP threading; build-essential is needed only
# for any wheels that have to compile from source.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libgomp1 ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# --- 4. Python deps ----------------------------------------------------------
# Copy ONLY the requirements first so Docker can cache this layer; if the
# code changes but deps don't, this 5-min step is reused from cache.
WORKDIR /app
COPY docker/requirements-victim.txt /app/requirements.txt
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

# --- 5. Application code -----------------------------------------------------
# Copy our Python package after deps so code edits don't bust the deps cache.
COPY src /app/src

# --- 6. Pre-fetch model weights (faster cold start) --------------------------
# DistilBERT is 250MB. If we download it at boot time, the first request takes
# 30s. Baking it in shifts that 30s into build time once.
# `|| echo` prevents build failure if the build sandbox is offline.
RUN python -c "from transformers import AutoTokenizer, AutoModel; \
  AutoTokenizer.from_pretrained('distilbert-base-uncased'); \
  AutoModel.from_pretrained('distilbert-base-uncased')" || echo "skip prefetch (offline)"

# --- 7. Network + entrypoint -------------------------------------------------
# Cloud Run / GKE will route HTTP traffic to port 8080.
EXPOSE 8080
CMD ["uvicorn", "src.victim_model.serve:app", "--host", "0.0.0.0", "--port", "8080"]
