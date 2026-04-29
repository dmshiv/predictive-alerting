output "loadgen_name"     { value = google_compute_instance.loadgen.name }
output "loadgen_zone"     { value = google_compute_instance.loadgen.zone }
output "loadgen_internal_ip" { value = google_compute_instance.loadgen.network_interface[0].network_ip }
output "ssh_command" {
  value = "gcloud compute ssh ${google_compute_instance.loadgen.name} --zone=${google_compute_instance.loadgen.zone} --tunnel-through-iap --project=${var.project_id}"
}
