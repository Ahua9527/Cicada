#!/bin/bash
# Purpose: Build signed Release Cicada.app (with helper binaries) and package it as a DMG.
# Run: bash apps/agent/native/sentinel-app/scripts/package-dmg.sh
# Requires: Xcode, valid Apple Development identity in keychain, swift toolchain.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/../../swift"
BUILD_DIR="$ROOT_DIR/.build"
CONFIGURATION="Release"
APP_NAME="Cicada"
APP_PATH="$BUILD_DIR/DerivedData/Build/Products/$CONFIGURATION/$APP_NAME.app"
DMG_DIR="$ROOT_DIR/dist"
DMG_PATH="$DMG_DIR/$APP_NAME.dmg"
HELPERS=(cicada cicada-agent cicada-sleephold)
IDENTITY="Apple Development"
ENTITLEMENTS="$ROOT_DIR/Sentry/Sentry.entitlements"

DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-$(security find-certificate -c 'Apple Development' -a -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU=\([^,]*\).*/\1/p' | head -1)}"
if [ -z "$DEVELOPMENT_TEAM" ]; then
  echo "❌ no Apple Development certificate found in keychain"
  exit 1
fi
echo "[dmg] signing team: $DEVELOPMENT_TEAM"

echo "[dmg] building swift helpers (release)..."
(cd "$SWIFT_DIR" && swift build -c release)
for HELPER in "${HELPERS[@]}"; do
  [ -x "$SWIFT_DIR/.build/release/$HELPER" ] || { echo "❌ missing helper: $HELPER"; exit 1; }
done

echo "[dmg] building sentinel app (Release, signed)..."
cd "$ROOT_DIR"
xcodebuild \
  -project Sentry.xcodeproj \
  -scheme Sentry \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGNING_ALLOWED=YES \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=CICADA_DISABLE_SIGNATURE_VALIDATION \
  build

[ -d "$APP_PATH" ] || { echo "❌ app not found: $APP_PATH"; exit 1; }

echo "[dmg] embedding helpers..."
mkdir -p "$APP_PATH/Contents/Helpers"
for HELPER in "${HELPERS[@]}"; do
  cp -f "$SWIFT_DIR/.build/release/$HELPER" "$APP_PATH/Contents/Helpers/$HELPER"
  chmod +x "$APP_PATH/Contents/Helpers/$HELPER"
done

echo "[dmg] re-signing bundle after helper embedding..."
codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

mkdir -p "$DMG_DIR"
rm -f "$DMG_PATH"
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "[dmg] creating $DMG_PATH ..."
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$STAGING"

echo "✅ DMG: $DMG_PATH"
