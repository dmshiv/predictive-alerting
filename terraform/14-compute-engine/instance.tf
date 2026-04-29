# =============================================================================
# WHAT  : One Debian e2-small VM running the traffic generator.
# WHY   : "Real" continuous load source (not a Cloud Function) so dashboards
#         look alive even when nobody is at the keyboard.
# HOW   : Startup script bootstraps systemd; SSH via IAP only.
# JD KEYWORDS: Compute Engine, Linux/Unix
# =============================================================================

data "terraform_remote_state" "vpc" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "01-vpc/state" }
}

data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "02-iam/state" }
}

data "terraform_remote_state" "ps" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "06-pubsub/state" }
}

data "terraform_remote_state" "ep" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "11-vertexai-endpoints/state" }
}

resource "google_compute_instance" "loadgen" {
  name         = "${local.name_prefix}-loadgen"
  machine_type = "e2-small"
  zone         = var.zone

  tags = ["loadgen", "sentinel"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
    }
  }

  network_interface {
    subnetwork = data.terraform_remote_state.vpc.outputs.subnet_self_link
    # No access_config block = no public IP. Egress via Cloud NAT.
  }

  service_account {
    email  = data.terraform_remote_state.iam.outputs.sa_email_traffic_gen
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
    sentinel-mode  = "baseline"   # read by traffic_generator.py from the metadata server
  }

  metadata_startup_script = templatefile("${path.module}/startup-script.sh.tftpl", {
    project_id     = var.project_id
    region         = var.region
    pubsub_topic   = data.terraform_remote_state.ps.outputs.topic_raw
    endpoint_full  = data.terraform_remote_state.ep.outputs.endpoint_full
    repo_url       = "https://github.com/your-org/sentinel-forecast.git"   # placeholder; start.sh can override via metadata
  })

  labels = {
    project = "sentinel-forecast"
    role    = "loadgen"
  }

  # If the startup-script changes, recreate (so the systemd unit reflects the new template)
  allow_stopping_for_update = true
}
