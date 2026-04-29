# =============================================================================
# WHAT  : Dual-purpose container - load generator OR telemetry collector.
# WHY   : Same image runs in two roles to keep image count low. The MODE env
#         var picks behaviour at startup:
#           MODE=loadgen   -> hammer the victim model with /recommend requests
#           MODE=collector -> read raw-traffic Pub/Sub, write to BigQuery
# HOW   : Tiny base, no ML deps. Mostly just GCP SDKs + requests.
# LAYMAN: This is the "noisy customer" robot OR the "audit clerk" robot,
#         depending which mode you switch on. We only need ONE recipe for both.
# =============================================================================

# --- 1. Base image -----------------------------------------------------------
FROM python:3.11-slim

# --- 2. Python runtime tweaks ------------------------------------------------
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1

# --- 3. Python deps (no apt install needed - tiny image) ---------------------
WORKDIR /app
COPY docker/requirements-traffic-gen.txt /app/requirements.txt
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

# --- 4. Application code -----------------------------------------------------
COPY src /app/src

# --- 5. Mode-selecting entrypoint --------------------------------------------
# Default is loadgen. Compute Engine VM sets MODE=collector via metadata when
# we want it to be the audit clerk instead.
ENV MODE=loadgen
CMD ["sh", "-c", "if [ \"$MODE\" = \"collector\" ]; then python -m src.ingestion.telemetry_collector; else python -m src.ingestion.traffic_generator; fi"]
