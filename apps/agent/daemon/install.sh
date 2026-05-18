#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CICADA_BIN="$HOME/.cicada/bin/cicada"

echo "================================"
echo "Cicada Daemon 安装（Swift Runtime）"
echo "================================"

if [ ! -x "$CICADA_BIN" ]; then
  echo "[1/2] 未检测到 $CICADA_BIN，先执行构建"
  bash "$ROOT_DIR/scripts/build.sh"
else
  echo "[1/2] 检测到 cicada 二进制: $CICADA_BIN"
fi

echo "[2/2] 安装 daemon LaunchAgent"
"$CICADA_BIN" daemon install

echo "✅ 安装完成"
