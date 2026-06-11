#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/swift"

swift test

cd "$ROOT_DIR/native/sentinel-app"
xcodebuild \
  test \
  -project Sentry.xcodeproj \
  -scheme Sentry \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO
