#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import json
import sys
import urllib.request


def fetch_json(url):
    with urllib.request.urlopen(url, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


try:
    milestones = fetch_json("https://chromiumdash.appspot.com/fetch_milestones")
    stable_milestones = [m for m in milestones if m.get("schedule_phase") == "stable"]
    if not stable_milestones:
        raise RuntimeError("stable milestone was not found")

    stable = max(stable_milestones, key=lambda m: int(m["milestone"]))
    milestone = int(stable["milestone"])
    milestone_details = fetch_json(f"https://chromiumdash.appspot.com/fetch_milestones?mstone={milestone}")
    webrtc_branch = milestone_details[0].get("webrtc_branch")
    if not webrtc_branch:
        raise RuntimeError(f"webrtc_branch was not found for M{milestone}")

    print(f"branch-heads/{webrtc_branch}")
except Exception as error:
    print(f"failed to resolve current WebRTC branch: {error}", file=sys.stderr)
    sys.exit(1)
PY
