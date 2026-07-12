#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[build] building swift runtime..."
cd "$ROOT_DIR/swift"
swift build -c release

echo "[build] swift runtime artifacts:"
echo "  $ROOT_DIR/swift/.build/release/cicada"
echo "  $ROOT_DIR/swift/.build/release/cicada-agent"
echo "  $ROOT_DIR/swift/.build/release/cicada-sleephold"

echo "[build] building sentinel app (if xcodebuild is available)..."
CICADA_HELPERS_SOURCE_DIR="$ROOT_DIR/swift/.build/release" bash "$ROOT_DIR/native/sentinel-app/scripts/build.sh"

echo "[build] sentinel app artifact:"
echo "  $ROOT_DIR/native/sentinel-app/.build/DerivedData/Build/Products/Release/Cicada.app"
echo "[build] done"
