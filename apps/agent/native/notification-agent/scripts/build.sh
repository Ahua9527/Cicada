#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v swift >/dev/null 2>&1; then
  echo "❌ 未检测到 swift。请安装 Xcode Command Line Tools。"
  exit 1
fi

if ! swift build -c release; then
  echo "❌ notifier 构建失败。"
  echo "可能原因："
  echo "  1) 网络无法拉取 NotchNotification 依赖"
  echo "  2) SPM 版本解析失败（from: 1.1.0）"
  echo "  3) 本机 Swift/Xcode Command Line Tools 异常"
  echo "可尝试：swift package reset && swift build -c release"
  exit 1
fi

echo "✅ notifier 构建完成: $ROOT_DIR/.build/release/cicada-notifier"
