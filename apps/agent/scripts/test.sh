#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_swiftpm_tests() {
  cd "$ROOT_DIR/swift"
  swift test
}

run_native_tests() {
  cd "$ROOT_DIR/native/sentinel-app"
  xcodebuild \
    test \
    -project Sentry.xcodeproj \
    -scheme Sentry \
    -destination "platform=macOS" \
    CODE_SIGNING_ALLOWED=NO
}

case "${1:-all}" in
  all)
    run_swiftpm_tests
    run_native_tests
    ;;
  swiftpm)
    run_swiftpm_tests
    ;;
  native)
    run_native_tests
    ;;
  *)
    echo "Usage: $0 [all|swiftpm|native]" >&2
    exit 2
    ;;
esac
