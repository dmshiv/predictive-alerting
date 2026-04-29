# =============================================================================
# WHAT  : Per-bucket IAM bindings to workload service accounts.
# WHY   : Each workload only sees the buckets it needs.
# JD KEYWORD: IAM, security
# =============================================================================

data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = {
    bucket = var.tfstate_bucket
    prefix = "02-iam/state"
  }
}

locals {
  sa_emails = data.terraform_remote_state.iam.outputs.sa_emails

  # Per-bucket access map: which SAs can read/write
  bucket_access = {
    raw_data  = { readers = ["pipeline","ingestion"],     writers = ["traffic_gen","ingestion"] }
    processed = { readers = ["pipeline","forecaster"],    writers = ["pipeline"] }
    models    = { readers = ["pipeline","victim","forecaster"], writers = ["pipeline"] }
    tb_logs   = { readers = ["pipeline","grafana"],       writers = ["pipeline"] }
    code      = { readers = ["pipeline"],                 writers = ["pipeline"] }
  }
}

resource "google_storage_bucket_iam_member" "readers" {
  for_each = merge([
    for bk, acl in local.bucket_access : {
      for sa in acl.readers : "${bk}-r-${sa}" => { bk = bk, sa = sa }
    }
  ]...)
  bucket = google_storage_bucket.buckets[each.value.bk].name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${local.sa_emails[each.value.sa]}"
}

resource "google_storage_bucket_iam_member" "writers" {
  for_each = merge([
    for bk, acl in local.bucket_access : {
      for sa in acl.writers : "${bk}-w-${sa}" => { bk = bk, sa = sa }
    }
  ]...)
  bucket = google_storage_bucket.buckets[each.value.bk].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${local.sa_emails[each.value.sa]}"
}
