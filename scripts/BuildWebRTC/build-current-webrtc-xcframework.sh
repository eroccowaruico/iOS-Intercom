#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WEBRTC_BRANCH="${WEBRTC_BRANCH:-$(${SCRIPT_DIR}/resolve-webrtc-branch.sh)}"
export WEBRTC_BRANCH

echo "Resolved WEBRTC_BRANCH=${WEBRTC_BRANCH}"
exec "${SCRIPT_DIR}/build-webrtc-xcframework.sh"
