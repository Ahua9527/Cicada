#!/usr/bin/env bash

#
# CicadaRelay 集成测试调试工具包装脚本
#
# 提供完整的端到端集成测试功能
#

set -euo pipefail

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

# 检查 Node.js 是否安装
check_node() {
    if ! command -v node &> /dev/null; then
        log_error "Node.js 未安装，请先安装 Node.js"
        exit 1
    fi
}

# 检查依赖是否安装
check_dependencies() {
    if [ ! -d "$PROJECT_ROOT/node_modules" ]; then
        log_warning "依赖未安装，正在安装..."
        cd "$PROJECT_ROOT"
        pnpm install
    fi
}

# 主函数
main() {
    check_node
    check_dependencies
    
    # 执行 Node.js 脚本
    cd "$PROJECT_ROOT"
    node "$SCRIPT_DIR/lib/debug-integration.js" "$@"
}

# 运行主函数
main "$@"

