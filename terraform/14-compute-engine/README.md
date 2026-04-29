# 14-compute-engine

**WHAT:** A small private Compute Engine VM running our `traffic_generator.py` as a systemd service.

**WHY:** This is the always-on baseline traffic generator. `chaos_inject.py` (run from your laptop) flips its mode for the demo.

**HOW:** e2-small Debian VM, no public IP (egress via Cloud NAT), startup-script clones the repo and installs the systemd unit.

**JD KEYWORDS:** Compute Engine, Linux/Unix
