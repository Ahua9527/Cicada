#!/bin/bash
# 编译并打包 Cicada.app 成 DMG 安装包。
# 用法：bash scripts/package-dmg.sh
# 产物：dist/Cicada-<时间戳>.dmg

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Cicada"
APP_PATH="apps/agent/native/sentinel-app/.build/DerivedData/Build/Products/Release/${APP_NAME}.app"
DIST_DIR="dist"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
STAGING_DIR="${DIST_DIR}/dmg-staging/Cicada-${TIMESTAMP}"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${TIMESTAMP}.dmg"

if [ ! -d "$APP_PATH" ]; then
  echo "❌ 未找到构建产物：$APP_PATH"
  echo "   先运行 pnpm run build:agent"
  exit 1
fi

# 准备 staging
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# 打 DMG
echo "[dmg] 创建 ${DMG_PATH} ..."
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

DMG_SIZE="$(du -h "$DMG_PATH" | cut -f1)"
echo "✅ 完成：${DMG_PATH}（${DMG_SIZE}）"