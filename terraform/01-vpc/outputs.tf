# =============================================================================
# WHAT  : Network outputs consumed by 13-gke, 14-compute-engine, 15-cloudrun.
# =============================================================================
output "vpc_id"            { value = google_compute_network.vpc.id }
output "vpc_self_link"     { value = google_compute_network.vpc.self_link }
output "vpc_name"          { value = google_compute_network.vpc.name }
output "subnet_id"         { value = google_compute_subnetwork.subnet.id }
output "subnet_self_link"  { value = google_compute_subnetwork.subnet.self_link }
output "subnet_name"       { value = google_compute_subnetwork.subnet.name }
output "armor_policy_id"   { value = try(google_compute_security_policy.armor[0].id, null) }
output "armor_policy_name" { value = try(google_compute_security_policy.armor[0].name, null) }
output "dns_zone_name"     { value = google_dns_managed_zone.internal.name }
