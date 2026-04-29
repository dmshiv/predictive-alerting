# =============================================================================
# WHAT  : Container for the Cloud Run "triage" service.
# WHY   : When forecaster publishes an incident, this service:
#         (1) clusters recent logs with sklearn,
#         (2) asks Gemini "what's the likely cause + 3 remediation steps?",
#         (3) posts a formatted summary to Slack and writes to BigQuery.
# HOW   : FastAPI HTTP service triggered by a Pub/Sub push subscription.
# LAYMAN: This is the "doctor on call" robot. When weatherman shouts about a
#         storm, this robot reads the symptoms and tells humans what to do.
# =============================================================================

# --- 1. Base image -----------------------------------------------------------
FROM python:3.11-slim

# --- 2. Python runtime tweaks ------------------------------------------------
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1

# --- 3. OS-level deps --------------------------------------------------------
# Just CA certs (HTTPS calls to Gemini + GCP). No native deps for sklearn.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates && rm -rf /var/lib/apt/lists/*

# --- 4. Python deps ----------------------------------------------------------
WORKDIR /app
COPY docker/requirements-triage.txt /app/requirements.txt
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

# --- 5. Application code -----------------------------------------------------
COPY src /app/src

# --- 6. Network + entrypoint -------------------------------------------------
# Cloud Run requires the service to listen on $PORT (default 8080).
EXPOSE 8080
CMD ["uvicorn", "src.triage.main:app", "--host", "0.0.0.0", "--port", "8080"]
