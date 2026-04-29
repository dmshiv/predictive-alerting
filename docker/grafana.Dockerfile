# =============================================================================
# WHAT  : Custom Grafana image with our dashboards + BigQuery datasource baked in.
# WHY   : Vanilla grafana/grafana doesn't know about our schemas. We pre-install
#         the plugins and JSON dashboard files so the container is "ready to
#         display" the moment Cloud Run starts it.
# HOW   : Extends the official grafana image, adds 2 plugins, copies dashboards,
#         writes a provisioning config so Grafana auto-discovers them at boot.
# LAYMAN: This is the "TV screen" image. We pre-load our charts onto it so the
#         humans don't have to click around to set them up every time.
# =============================================================================

# --- 1. Base image (official Grafana) ----------------------------------------
FROM grafana/grafana:11.3.0

# --- 2. Switch to root to install plugins ------------------------------------
USER root

# --- 3. Install datasource plugins -------------------------------------------
# Sheets plugin is best-effort (some networks block its catalog) - hence ||true.
# BigQuery plugin is required for our dashboards -> must succeed.
RUN grafana-cli plugins install grafana-google-sheets-datasource || true \
 && grafana-cli plugins install grafana-bigquery-datasource

# --- 4. Bake in our dashboard JSON files -------------------------------------
# These are the .json files in src/dashboards/grafana/. Grafana's provisioner
# (next step) will pick them up automatically.
COPY src/dashboards/grafana /var/lib/grafana/dashboards/sentinel/

# --- 5. Tell Grafana where the dashboards live -------------------------------
# We write a tiny YAML config that Grafana reads at boot. printf is used here
# because the legacy docker builder doesn't support heredoc syntax.
RUN mkdir -p /etc/grafana/provisioning/dashboards /etc/grafana/provisioning/datasources
RUN printf '%s\n' \
    'apiVersion: 1' \
    'providers:' \
    '  - name: sentinel' \
    '    folder: Sentinel' \
    '    type: file' \
    '    options:' \
    '      path: /var/lib/grafana/dashboards/sentinel' \
    > /etc/grafana/provisioning/dashboards/sentinel.yaml

# --- 5b. Provision the BigQuery + Cloud Monitoring datasources --------------
# authenticationType=gce makes the plugin use the Cloud Run service account
# via the GCE metadata server; no key files needed. defaultProject is read
# from the GCP_PROJECT_ID env var that Cloud Run injects at runtime, with a
# safe fallback so the YAML stays valid even outside Cloud Run.
RUN printf '%s\n' \
    'apiVersion: 1' \
    'datasources:' \
    '  - name: BigQuery' \
    '    uid: sentinel-bq' \
    '    type: grafana-bigquery-datasource' \
    '    access: proxy' \
    '    isDefault: true' \
    '    jsonData:' \
    '      authenticationType: gce' \
    '      defaultProject: ${GCP_PROJECT_ID:sentinel-forecast-2544}' \
    '      processingProject: ${GCP_PROJECT_ID:sentinel-forecast-2544}' \
    '      defaultDataset: sentinel_dev_incidents' \
    '      processingLocation: us-central1' \
    '      queryPriority: INTERACTIVE' \
    '    editable: true' \
    '  - name: Cloud Monitoring' \
    '    uid: sentinel-cm' \
    '    type: stackdriver' \
    '    access: proxy' \
    '    jsonData:' \
    '      authenticationType: gce' \
    '      defaultProject: ${GCP_PROJECT_ID:sentinel-forecast-2544}' \
    '    editable: true' \
    > /etc/grafana/provisioning/datasources/sentinel.yaml

# --- 6. Drop back to non-root + expose port ----------------------------------
# Grafana refuses to run as root in production mode. Cloud Run will route HTTP
# traffic to port 3000.
# Datasources (BigQuery project ID etc) are injected via env vars at runtime.
USER grafana
EXPOSE 3000
