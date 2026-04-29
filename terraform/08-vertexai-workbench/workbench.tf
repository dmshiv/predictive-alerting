# =============================================================================
# WHAT  : Vertex AI Workbench instance (managed JupyterLab).
# WHY   : Interactive notebook env without managing a VM yourself.
# HOW   : e2-standard-4 = 4 vCPU / 16 GB RAM (~$0.13/h) — small enough for demo,
#         big enough to run light training. Stop the instance to save cost.
# JD KEYWORD: Vertex AI Workbench
# =============================================================================

data "terraform_remote_state" "vpc" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "01-vpc/state" }
}

data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "02-iam/state" }
}

resource "google_workbench_instance" "wb" {
  provider = google-beta
  name     = "${local.name_prefix}-workbench"
  location = var.zone

  gce_setup {
    machine_type = "e2-standard-4"

    vm_image {
      project = "cloud-notebooks-managed"
      family  = "workbench-instances"
    }

    network_interfaces {
      network    = data.terraform_remote_state.vpc.outputs.vpc_self_link
      subnet     = data.terraform_remote_state.vpc.outputs.subnet_self_link
      nic_type   = "GVNIC"
    }

    service_accounts {
      email = data.terraform_remote_state.iam.outputs.sa_email_pipeline
    }

    disable_public_ip = false   # set true if you want fully private; need IAP tunnel then
    metadata = {
      idle-timeout-seconds = "3600"   # auto-shutdown after 1h idle (cost control)
    }

    tags = ["workbench", "sentinel"]
  }

  labels = {
    project = "sentinel-forecast"
  }
}
