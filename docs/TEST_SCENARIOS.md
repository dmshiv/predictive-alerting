# Test Scenarios — How to Provoke (and Watch) Each Failure Mode

These are the demo scripts. Each scenario is a 5-step recipe:

1. **Set the chaos mode**
2. **Watch the live signal go bad in Grafana**
3. **See AI #2 forecast the breach**
4. **See the predictive alert hit triage**
5. **Reset to baseline**

Open Grafana **before** you start so you can see the signal turn.

---

## Scenario A — Input Distribution Drift  (the "selfie problem")

**Story:** Customers stop uploading studio shots and start uploading selfies.
The image-embedding norm distribution shifts. The recommender's accuracy
quietly degrades. p99 latency creeps up because the image branch hits
out-of-distribution inputs.

**Steps:**

1. Inject the chaos:
   ```bash
   ./scripts/chaos_inject.py --mode=drift
   ```

2. **Watch (Grafana - "Sentinel · Overview" dashboard):**
   - `image_embedding_norm` panel: mean climbs from ~1.0 to ~1.3 within 2-3 min.
   - Latency p95 panel: climbs gradually from ~120ms toward 200ms.

3. **Watch (BigQuery):**
   ```sql
   SELECT * FROM `PROJECT.sentinel_dev_features.predictions`
   WHERE metric_name = 'image_embedding_norm'
     AND predicted_at > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE)
   ORDER BY predicted_at DESC LIMIT 20;
   ```
   You should see `predicted_value` rising AND `upper_bound` crossing 1.20 within ~5–10 min.

4. **Triage fires** within ~5 min after the forecaster starts predicting a breach.
   - Cloud Logging filter:
     ```
     jsonPayload.event="predictive_alert"
     ```
   - Slack/email (if configured): alert posted with Gemini report and runbook
     `refresh_features` or `rollback_model`.

5. **Reset:**
   ```bash
   ./scripts/chaos_inject.py --mode=baseline
   ```
   `image_embedding_norm` returns to ~1.0 within 2-3 min; the next forecaster
   run no longer fires.

**Why this matters:** Drift is the #1 silent ML failure mode. We caught it ~5–15 min before SLO breach.

---

## Scenario B — Latency Injection  (the "infra is dying" problem)

**Story:** A bad noisy neighbor or a slow downstream service makes the model's
p99 spike from 120ms to 700ms.

**Steps:**

1. ```bash
   ./scripts/chaos_inject.py --mode=latency
   ```

2. **Grafana:** latency panel jumps to ~700ms within 60s.

3. **BigQuery:**
   ```sql
   SELECT minute, metric_name, AVG(metric_value) AS v
     FROM `PROJECT.sentinel_dev_features.telemetry_1m_rollup`
    WHERE minute > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE)
      AND metric_name = 'latency_ms'
    GROUP BY 1,2 ORDER BY 1;
   ```

4. **Predictive alert** fires with `metric_name=latency_ms`, `severity=high`. Recommended runbook: `scale_pods`.

5. ```bash
   ./scripts/chaos_inject.py --mode=baseline
   ```

---

## Scenario C — Traffic Burst  (the "we got Reddit-hugged" problem)

**Story:** A viral mention sends traffic from 30 req/s to 200 req/s. We need pods to scale before customers see errors.

**Steps:**

1. ```bash
   ./scripts/chaos_inject.py --mode=burst
   ```

2. **Grafana → "Infrastructure" dashboard:**
   - Cloud Run instance count climbs.
   - GKE pod count climbs.

3. **Vertex AI → Endpoint metrics:** request count climbs ~7x.

4. Optionally see HPA decisions:
   ```
   gcloud container clusters get-credentials sentinel-dev-gke --region=us-central1
   kubectl describe hpa -n sentinel
   ```

5. ```bash
   ./scripts/chaos_inject.py --mode=baseline
   ```

---

## Scenario D — Error Rate Spike  (the "model just broke" problem)

**Story:** Latency mode also flips a small fraction (~5%) of responses to errors.
This tests the auto-remediation path:

- AI #2 forecasts `error_rate > 0.02` within the 2h horizon.
- Triage receives the alert.
- Runbook recommender suggests `disable_endpoint`.
- Auto-remediation logs an `approval_required` (we don't auto-disable in the demo — too dangerous; flip `AUTO_REMEDIATE=true` in Cloud Run env to live-fire).

---

## Scenario E — All Quiet  (the "production is healthy" baseline)

The default. Use it to:

- Confirm the system **doesn't** fire false positives.
- Show what a healthy ml-ops dashboard looks like for stakeholders.
- Let TensorBoard / pipelines run on real data while idle.

```bash
./scripts/chaos_inject.py --mode=baseline
```

---

## Smoke Test (run this every time before a demo)

```bash
./scripts/smoke_test.sh
```

It hits every layer: Pub/Sub publish, BigQuery write, Vertex AI predict,
Cloud Run /healthz, forecaster predict, and a synthetic alert through the
triage service. Should print `PASS=5  FAIL=0`.
