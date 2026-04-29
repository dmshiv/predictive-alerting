# 00-globals

**WHAT:** Project-wide setup. Enables every GCP API the rest of the project will need, and exports common variables (project_id, region, env_name) for downstream folders to reuse.

**WHY:** GCP APIs are disabled by default. If we don't enable them up-front, the very first `terraform apply` in a downstream folder will fail with `SERVICE_DISABLED`.

**HOW:** Run after `scripts/bootstrap.sh` has created the tfstate bucket. This folder has nothing to destroy that matters — disabling APIs in `destroy` is intentionally NOT done, because that can break other resources still using them. Hence `enable_destroy_protection = true` style on services.

**DEPENDS ON:** Nothing (this is the root). `bootstrap.sh` must have run first.

**NEXT FOLDER:** `01-vpc`
