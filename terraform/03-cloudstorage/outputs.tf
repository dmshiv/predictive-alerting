# Bucket names exported for downstream consumers.
output "buckets" {
  value = { for k, b in google_storage_bucket.buckets : k => b.name }
}
output "bucket_raw_data"  { value = google_storage_bucket.buckets["raw_data"].name }
output "bucket_processed" { value = google_storage_bucket.buckets["processed"].name }
output "bucket_models"    { value = google_storage_bucket.buckets["models"].name }
output "bucket_tb_logs"   { value = google_storage_bucket.buckets["tb_logs"].name }
output "bucket_code"      { value = google_storage_bucket.buckets["code"].name }
