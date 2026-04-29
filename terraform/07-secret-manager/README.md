# 07-secret-manager

**WHAT:** Secret containers (placeholders) for: Gemini API key, Slack webhook URL, alert email target.

**WHY:** Never commit secrets. Containers are created here; values are written by `setup_slack.sh` / `setup_email.sh` / manual `gcloud secrets versions add`.

**HOW:** `google_secret_manager_secret` for the container; values added by scripts. IAM grants accessor role to the right SAs.
