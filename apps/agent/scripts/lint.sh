#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/swift"

echo "[lint] 执行 swift build 作为语法/编译校验"
swift build

echo "[lint] 执行 sentinel app Debug 编译校验"
cd "$ROOT_DIR/native/sentinel-app"
xcodebuild \
  -project Sentry.xcodeproj \
  -scheme Sentry \
  -configuration Debug \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null
