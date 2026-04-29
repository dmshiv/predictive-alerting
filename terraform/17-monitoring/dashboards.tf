# =============================================================================
# WHAT  : Cloud Monitoring native dashboard.
# WHY   : Always-works backup to Grafana.
# HOW   : JSON template of widgets.
# =============================================================================

resource "google_monitoring_dashboard" "system" {
  dashboard_json = jsonencode({
    displayName = "Sentinel · System Overview"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width  = 6, height = 4
          widget = {
            title = "Triage uptime"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" resource.type=\"uptime_url\""
                    aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_FRACTION_TRUE" }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          xPos = 6, width = 6, height = 4
          widget = {
            title = "Cloud Run request count"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\""
                    aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_RATE" }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          yPos = 4, width = 12, height = 4
          widget = {
            title = "Predictive alerts fired (counter)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.predictive_alerts.name}\""
                    aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_RATE" }
                  }
                }
                plotType = "STACKED_BAR"
              }]
            }
          }
        }
      ]
    }
  })
}
