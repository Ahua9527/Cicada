#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
CONFIGURATION="${CONFIGURATION:-Release}"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "❌ 未检测到 xcodebuild。请安装 Xcode。"
  exit 1
fi

cd "$ROOT_DIR"

xcodebuild \
  -project Sentry.xcodeproj \
  -scheme Sentry \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=CICADA_DISABLE_SIGNATURE_VALIDATION \
  build

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/$CONFIGURATION/Sentry.app"
INSTALL_DIR="$HOME/.cicada/apps"

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/Sentry.app"
cp -R "$APP_PATH" "$INSTALL_DIR/Sentry.app"

echo "✅ Sentinel app installed to $INSTALL_DIR/Sentry.app"
