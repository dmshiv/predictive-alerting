# =============================================================================
# WHAT  : Five GCS buckets with lifecycle rules per purpose.
# WHY   : Separation of concerns + automatic cost control.
# JD KEYWORD: Cloud Storage
# =============================================================================

locals {
  buckets = {
    raw_data    = { suffix = "raw-data",    desc = "incoming product/review data",     ttl_days = 30 }
    processed   = { suffix = "processed",   desc = "feature-engineered training",      ttl_days = 90 }
    models      = { suffix = "models",      desc = "trained model artifacts",          ttl_days = 0  }   # keep forever
    tb_logs     = { suffix = "tb-logs",     desc = "TensorBoard event files",          ttl_days = 14 }
    code        = { suffix = "code",        desc = "pipeline staging",                 ttl_days = 0  }
  }
}

resource "google_storage_bucket" "buckets" {
  for_each = local.buckets

  name                        = "${var.project_id}-${local.name_prefix}-${each.value.suffix}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = each.key == "models" || each.key == "code"
  }

  dynamic "lifecycle_rule" {
    for_each = each.value.ttl_days > 0 ? [1] : []
    content {
      action { type = "Delete" }
      condition { age = each.value.ttl_days }
    }
  }

  # Move processed data to Coldline after 30 days (cheaper)
  dynamic "lifecycle_rule" {
    for_each = each.key == "processed" ? [1] : []
    content {
      action {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
      condition {
        age = 30
      }
    }
  }

  labels = {
    project = "sentinel-forecast"
    purpose = each.value.suffix
  }
}
