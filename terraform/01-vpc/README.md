# 01-vpc

**WHAT:** Private virtual network for the entire project — VPC + subnets, Cloud NAT for egress, Cloud DNS private zone, firewall rules, and Cloud Armor security policy.

**WHY:** Everything else (GKE, Compute VM, Cloud Run direct VPC egress) lives inside this network. Without it, resources end up on the default VPC which has loose firewall rules and is harder to troubleshoot — exactly what a TSE customer ticket usually involves.

**HOW:** One custom-mode VPC, one /24 subnet per region, Cloud NAT so private VMs can reach the internet (and Vertex/GCS), private DNS zone for internal service names, deny-all + allow-internal firewall rules.

**JD KEYWORDS:** TCP/IP · DNS · Load Balancing · Routing

**DEPENDS ON:** `00-globals` (for project_id, region, name_prefix)

**EXPORTS:** `vpc_id`, `subnet_id`, `subnet_self_link` (consumed by 13-gke, 14-compute-engine, 15-cloudrun)
