# =============================================================================
# WHAT  : Container for AI #2 (the forecaster). Runs predict_breach.py in a loop.
# WHY   : This robot reads telemetry every minute and predicts whether the
#         victim model will breach SLO in the next 15 min. If yes -> publish
#         to incidents Pub/Sub topic.
# HOW   : Slim Python + tensorflow-cpu + sklearn + GCP SDKs. No HTTP server.
# LAYMAN: This is the "weatherman" robot. Looks at recent metrics and forecasts
#         "in 15 minutes there will be a storm (latency spike)".
# =============================================================================

# --- 1. Base image -----------------------------------------------------------
FROM python:3.11-slim

# --- 2. Python runtime tweaks ------------------------------------------------
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1

# --- 3. OS-level deps --------------------------------------------------------
# tensorflow needs libgomp1 (OpenMP). ca-certificates so HTTPS calls to GCP work.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 ca-certificates && rm -rf /var/lib/apt/lists/*

# --- 4. Python deps (cache-friendly: copy requirements first) ----------------
WORKDIR /app
COPY docker/requirements-forecaster.txt /app/requirements.txt
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

# --- 5. Application code -----------------------------------------------------
COPY src /app/src

# --- 6. Entrypoint -----------------------------------------------------------
# MODE=detector tells the script to run the prediction loop (vs train mode).
# --loop: re-evaluate every 60s, never exit (k8s/Compute Engine restart on crash).
ENV MODE=detector
CMD ["python", "-m", "src.forecaster.predict_breach", "--loop"]
