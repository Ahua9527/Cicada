#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
CONFIGURATION="${CONFIGURATION:-Release}"
HELPERS_SOURCE_DIR="${CICADA_HELPERS_SOURCE_DIR:-$ROOT_DIR/../../swift/.build/release}"
REQUIRE_HELPERS=0
if [ -n "${CICADA_HELPERS_SOURCE_DIR:-}" ]; then
  REQUIRE_HELPERS=1
fi

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
HELPERS_DIR="$APP_PATH/Contents/Helpers"
HELPERS=(cicada cicada-agent cicada-sleephold)

if [ -d "$HELPERS_SOURCE_DIR" ]; then
  mkdir -p "$HELPERS_DIR"
  for HELPER in "${HELPERS[@]}"; do
    SOURCE="$HELPERS_SOURCE_DIR/$HELPER"
    if [ ! -x "$SOURCE" ]; then
      echo "❌ missing executable helper: $SOURCE"
      exit 1
    fi
    cp -f "$SOURCE" "$HELPERS_DIR/$HELPER"
    chmod +x "$HELPERS_DIR/$HELPER"
  done
  echo "✅ Helpers embedded in $APP_PATH/Contents/Helpers"
elif [ "$REQUIRE_HELPERS" -eq 1 ]; then
  echo "❌ helper source directory not found: $HELPERS_SOURCE_DIR"
  exit 1
else
  echo "[sentinel] helper source directory not found; skipping helper embedding"
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/Sentry.app"
cp -R "$APP_PATH" "$INSTALL_DIR/Sentry.app"

echo "✅ Sentinel app installed to $INSTALL_DIR/Sentry.app"
