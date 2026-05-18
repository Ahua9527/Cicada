#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/swift"

echo "[lint] 执行 swift build 作为语法/编译校验"
swift build
