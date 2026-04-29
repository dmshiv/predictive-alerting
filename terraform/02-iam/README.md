# 02-iam

**WHAT:** Service accounts (one per workload) plus least-privilege role bindings, plus Workload Identity bindings so GKE pods can authenticate as GSAs without keys.

**WHY:** Default Compute Engine SA is over-privileged and shared by everything — a TSE anti-pattern. We give each workload its own SA, with only the roles it strictly needs.

**HOW:** One google_service_account per workload + project-level role bindings via google_project_iam_member.

**DEPENDS ON:** `00-globals`

**EXPORTS:** `sa_email_<workload>` for downstream folders to attach to their resources.
