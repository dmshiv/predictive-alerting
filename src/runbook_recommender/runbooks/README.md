# Runbooks

Each YAML here is a "what-to-do" for a class of incident. They're loaded by
`src/runbook_recommender/recommender.py` and matched by tags.

To add a new runbook:
1. Copy any existing YAML.
2. Set `runbook_id`, `title`, `when_to_use` tags, and `actions` steps.
3. Restart the triage Cloud Run service (or redeploy).
