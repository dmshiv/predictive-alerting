output "cluster_name"     { value = google_container_cluster.autopilot.name }
output "cluster_endpoint" { value = google_container_cluster.autopilot.endpoint }
output "cluster_location" { value = google_container_cluster.autopilot.location }
output "namespace"        { value = kubernetes_namespace.sentinel.metadata[0].name }
