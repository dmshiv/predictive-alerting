# =============================================================================
# WHAT  : Private GKE Autopilot cluster.
# WHY   : Autopilot = we don't manage nodes; just pay per pod. Lower ops cost,
#         secure-by-default, perfect for a demo.
# HOW   : Private cluster (no public node IPs), workload identity enabled.
# JD KEYWORD: Kubernetes
# =============================================================================

data "terraform_remote_state" "vpc" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "01-vpc/state" }
}

resource "google_container_cluster" "autopilot" {
  name     = "${local.name_prefix}-gke"
  location = var.region

  enable_autopilot = true
  deletion_protection = false

  network    = data.terraform_remote_state.vpc.outputs.vpc_self_link
  subnetwork = data.terraform_remote_state.vpc.outputs.subnet_self_link

  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false   # keep public endpoint for kubectl from your laptop
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "open (demo) — tighten in prod"
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel { channel = "REGULAR" }
}
