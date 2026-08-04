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

# 签名校验：未签名的 .app 打成 DMG 会被 Gatekeeper 拒绝，打包前快速失败。
if ! codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
  echo "❌ 应用未签名或签名校验失败：$APP_PATH"
  echo "   请先对构建产物完成代码签名再打包"
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