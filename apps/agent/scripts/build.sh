#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[build] building swift runtime..."
cd "$ROOT_DIR/swift"
swift build -c release

mkdir -p "$HOME/.cicada/bin"
cp -f "$ROOT_DIR/swift/.build/release/cicada" "$HOME/.cicada/bin/cicada"
cp -f "$ROOT_DIR/swift/.build/release/cicada-agent" "$HOME/.cicada/bin/cicada-agent"
cp -f "$ROOT_DIR/swift/.build/release/cicada-sleephold" "$HOME/.cicada/bin/cicada-sleephold"
chmod +x "$HOME/.cicada/bin/cicada" "$HOME/.cicada/bin/cicada-agent" "$HOME/.cicada/bin/cicada-sleephold"

echo "[build] swift runtime binaries installed to ~/.cicada/bin"

for CANDIDATE in "/opt/homebrew/bin" "/usr/local/bin" "$HOME/.local/bin"; do
  if [ -d "$CANDIDATE" ] && [ -w "$CANDIDATE" ]; then
    ln -sf "$HOME/.cicada/bin/cicada" "$CANDIDATE/cicada"
    echo "[build] linked cicada -> $CANDIDATE/cicada"
    break
  fi
done

echo "[build] building sentinel app (if xcodebuild is available)..."
bash "$ROOT_DIR/native/sentinel-app/scripts/build.sh"

echo "[build] done"
