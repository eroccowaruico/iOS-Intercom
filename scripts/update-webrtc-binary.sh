#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPOSITORY_PARENT="$(cd "${REPOSITORY_ROOT}/.." && pwd)"

default_developer_dir() {
  local selected=""
  selected="$(xcode-select -p 2>/dev/null || true)"
  if [[ -n "${selected}" && "${selected}" != *CommandLineTools* ]]; then
    echo "${selected}"
    return
  fi

  local xcode_app=""
  xcode_app="$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null | head -1 || true)"
  if [[ -n "${xcode_app}" && -d "${xcode_app}/Contents/Developer" ]]; then
    echo "${xcode_app}/Contents/Developer"
    return
  fi

  echo "${selected}"
}

RTC_PACKAGE_DIR="${RTC_PACKAGE_DIR:-${REPOSITORY_ROOT}/RideIntercom/packages/RTC}"
WEBRTC_BUILD_ROOT="${WEBRTC_BUILD_ROOT:-${REPOSITORY_PARENT}/webrtc-build}"
DEPOT_TOOLS_DIR="${DEPOT_TOOLS_DIR:-${REPOSITORY_PARENT}/depot_tools}"
DEVELOPER_DIR="${DEVELOPER_DIR:-$(default_developer_dir)}"
WEBRTC_BRANCH="${WEBRTC_BRANCH:-}"
IOS="${IOS:-true}"
MACOS="${MACOS:-true}"
MAC_CATALYST="${MAC_CATALYST:-false}"
REQUIRE_CATALYST="${REQUIRE_CATALYST:-false}"
ALLOW_ASSEMBLE_RECOVERY="${ALLOW_ASSEMBLE_RECOVERY:-true}"
RUN_SWIFTPM_VALIDATION="${RUN_SWIFTPM_VALIDATION:-true}"
RUN_TESTS="${RUN_TESTS:-true}"

export WEBRTC_BUILD_ROOT DEPOT_TOOLS_DIR DEVELOPER_DIR IOS MACOS MAC_CATALYST

usage() {
  cat <<USAGE
Usage:
  $0

This is the normal one-command workflow. It resolves the WebRTC branch,
builds WebRTC.xcframework, verifies headers, imports the zip into the RTC
package binary target, clears stale SwiftPM binary caches, and validates the
RTC package.

Common overrides:
  WEBRTC_BRANCH=branch-heads/7727   Build a fixed WebRTC branch.
  IOS=true|false                    Include iOS device/simulator slices. Default: ${IOS}
  MACOS=true|false                  Include macOS universal slice. Default: ${MACOS}
  MAC_CATALYST=true|false           Try Catalyst slice. Default: ${MAC_CATALYST}
  REQUIRE_CATALYST=true             Fail instead of falling back when Catalyst fails.
  RUN_TESTS=false                   Skip RTC package tests after import.
  RUN_SWIFTPM_VALIDATION=false      Skip RTCNativeWebRTC build validation.
USAGE
}

log_step() {
  echo
  echo "==> $1"
}

die_with_doctor_hint() {
  echo >&2
  echo "WebRTC binary update failed." >&2
  echo "Run this diagnostic command for the next concrete action:" >&2
  echo "  cd ${REPOSITORY_ROOT}" >&2
  echo "  scripts/doctor-webrtc-binary.sh" >&2
  exit 1
}

require_file() {
  local path="$1"
  local message="$2"
  if [[ ! -e "${path}" ]]; then
    echo "Missing: ${path}" >&2
    echo "${message}" >&2
    exit 1
  fi
}

has_base_framework_outputs() {
  [[ -d "${WEBRTC_BUILD_ROOT}/src/out/ios-arm64-device/WebRTC.framework" \
    && -d "${WEBRTC_BUILD_ROOT}/src/out/ios-x64-simulator/WebRTC.framework" \
    && -d "${WEBRTC_BUILD_ROOT}/src/out/ios-arm64-simulator/WebRTC.framework" \
    && -d "${WEBRTC_BUILD_ROOT}/src/out/macos-x64/WebRTC.framework" \
    && -d "${WEBRTC_BUILD_ROOT}/src/out/macos-arm64/WebRTC.framework" ]]
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

trap die_with_doctor_hint ERR

log_step "Checking prerequisites"
require_file "${DEVELOPER_DIR}/usr/bin/xcodebuild" "Set DEVELOPER_DIR to an installed Xcode Developer directory."
require_file "${DEPOT_TOOLS_DIR}/gclient" "Set DEPOT_TOOLS_DIR to the directory containing depot_tools."
require_file "${DEPOT_TOOLS_DIR}/fetch" "Set DEPOT_TOOLS_DIR to the directory containing depot_tools."

if [[ -z "${WEBRTC_BRANCH}" ]]; then
  log_step "Resolving current WebRTC branch"
  WEBRTC_BRANCH="$(${SCRIPT_DIR}/resolve-webrtc-branch.sh)"
fi
export WEBRTC_BRANCH
echo "WEBRTC_BRANCH=${WEBRTC_BRANCH}"

log_step "Building WebRTC.xcframework"
set +e
"${SCRIPT_DIR}/build-webrtc-xcframework.sh"
build_status=$?
set -e

if [[ "${build_status}" -ne 0 ]]; then
  echo "Initial WebRTC build failed with exit code ${build_status}." >&2
  if [[ "${ALLOW_ASSEMBLE_RECOVERY}" == "true" && "${REQUIRE_CATALYST}" != "true" && has_base_framework_outputs ]]; then
    log_step "Recovering by assembling existing iOS + macOS outputs without Catalyst"
    IOS=true MACOS=true MAC_CATALYST=false ASSEMBLE_ONLY=true "${SCRIPT_DIR}/build-webrtc-xcframework.sh"
  else
    echo "Automatic recovery is not available." >&2
    echo "Expected iOS/macOS framework outputs were not complete, or Catalyst is required." >&2
    false
  fi
fi

log_step "Verifying generated WebRTC.xcframework"
"${SCRIPT_DIR}/verify-webrtc-xcframework.sh" "${WEBRTC_BUILD_ROOT}/src/out/WebRTC.xcframework"

log_step "Importing WebRTC binary target into RTC package"
"${SCRIPT_DIR}/import-webrtc-xcframework.sh"

log_step "Clearing stale SwiftPM WebRTC binary caches"
CLEAN_MODE=swiftpm DRY_RUN=false "${SCRIPT_DIR}/clean-webrtc-build-resources.sh"

if [[ "${RUN_SWIFTPM_VALIDATION}" == "true" ]]; then
  log_step "Building RTCNativeWebRTC with imported binary target"
  (cd "${RTC_PACKAGE_DIR}" && "${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" build --target RTCNativeWebRTC)
fi

if [[ "${RUN_TESTS}" == "true" ]]; then
  log_step "Running RTC package tests"
  (cd "${RTC_PACKAGE_DIR}" && "${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" test)
fi

log_step "WebRTC binary update completed"
cat <<SUMMARY
Imported artifact:
  ${RTC_PACKAGE_DIR}/BinaryArtifacts/WebRTC/WebRTC.xcframework.zip

Metadata:
  ${RTC_PACKAGE_DIR}/BinaryArtifacts/WebRTC/WebRTC.xcframework.metadata

Optional cleanup after you confirm the app builds:
  CLEAN_MODE=build-output DRY_RUN=false scripts/clean-webrtc-build-resources.sh

Keep the source checkout when you expect to rebuild soon:
  ${WEBRTC_BUILD_ROOT}
SUMMARY