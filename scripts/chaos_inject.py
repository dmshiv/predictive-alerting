#!/usr/bin/env python3
"""
============================================================
WHAT  : Flip the load-gen VM's "mode" (baseline / drift / latency / burst / off).
WHY   : The whole demo hinges on being able to provoke a failure mode and watch
        the system catch it. This script is the "demo button".
HOW   : Adds VM metadata `sentinel-mode=<MODE>`. The traffic_generator.py
        running on the VM polls metadata every iteration and adapts.
LAYMAN: A remote control with 5 buttons: NORMAL / SHIFT-INPUTS / SLOWDOWN /
        FLOOD / OFF. Press one and the VM acts that way.
USAGE : ./scripts/chaos_inject.py --mode=drift
============================================================
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

VALID_MODES = ["baseline", "drift", "latency", "burst", "off"]


def main() -> int:
    parser = argparse.ArgumentParser(description="Set the chaos mode on the load-gen VM.")
    parser.add_argument("--mode", required=True, choices=VALID_MODES,
                        help="What kind of traffic to generate.")
    parser.add_argument("--project", default=os.environ.get("GCP_PROJECT_ID"))
    parser.add_argument("--zone", default=os.environ.get("GCP_ZONE", os.environ.get("GCP_REGION", "us-central1") + "-a"))
    parser.add_argument("--env-name", default=os.environ.get("ENV_NAME", "dev"))
    args = parser.parse_args()

    if not args.project:
        print("ERROR: GCP_PROJECT_ID not set (source .env first).", file=sys.stderr)
        return 2

    instance = f"sentinel-{args.env_name}-loadgen"
    print(f">>> setting mode '{args.mode}' on {instance} ({args.zone})")

    cmd = [
        "gcloud", "compute", "instances", "add-metadata", instance,
        f"--metadata=sentinel-mode={args.mode}",
        f"--zone={args.zone}",
        f"--project={args.project}",
        "--quiet",
    ]
    res = subprocess.run(cmd)
    if res.returncode != 0:
        print(f"ERROR: gcloud command failed (exit {res.returncode})", file=sys.stderr)
        return res.returncode

    msg = {
        "baseline": "back to healthy traffic",
        "drift":    "input distribution shift — forecaster should fire in ~5-15 min",
        "latency":  "latency injection — alert in ~3-10 min",
        "burst":    "traffic spike — HPA should react",
        "off":      "load gen paused (no traffic)",
    }[args.mode]
    print(f">>> {msg}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
