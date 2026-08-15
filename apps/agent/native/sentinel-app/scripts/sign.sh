#!/bin/bash
# 对 Release 构建产物 Cicada.app 整体代码签名（框架 → helpers → 主程序），并校验。
# 用法：bash apps/agent/native/sentinel-app/scripts/sign.sh
# 要求：先 pnpm run build:agent；钥匙串有签名身份（security find-identity -v -p codesigning）。
#   默认取第一个 "Apple Development" 身份，可用 CICADA_SIGN_IDENTITY 覆盖，
#   如 CICADA_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENTINEL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${CICADA_APP_PATH:-$SENTINEL_DIR/.build/DerivedData/Build/Products/Release/Cicada.app}"
APP_ENTITLEMENTS="$SENTINEL_DIR/Sentry/Sentry.entitlements"

# 签名身份：默认自动探测第一个 Apple Development 身份（本机开发/自测），
# 正式发布用 CICADA_SIGN_IDENTITY 显式指定 Developer ID。
IDENTITY="${CICADA_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$IDENTITY" ]; then
  echo "❌ 未找到可用签名身份。用 security find-identity -v -p codesigning 检查钥匙串。"
  exit 1
fi

if [ ! -d "$APP_PATH" ]; then
  echo "❌ 未找到构建产物：$APP_PATH"
  echo "   先运行 pnpm run build:agent"
  exit 1
fi

echo "[sign] identity: $IDENTITY"
echo "[sign] app: $APP_PATH"

# 由内到外：先框架动态库，再 helpers，最后主程序（带沙箱 entitlements）。
if [ -d "$APP_PATH/Contents/Frameworks" ]; then
  find "$APP_PATH/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "*.framework" \) | while read -r ITEM; do
    codesign --force --sign "$IDENTITY" "$ITEM"
  done
fi

if [ -d "$APP_PATH/Contents/Helpers" ]; then
  for HELPER in "$APP_PATH/Contents/Helpers"/*; do
    codesign --force --sign "$IDENTITY" "$HELPER"
  done
fi

codesign --force --sign "$IDENTITY" --entitlements "$APP_ENTITLEMENTS" "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH"
echo "✅ 签名完成并通过 --deep --strict 校验"
