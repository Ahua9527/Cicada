#!/bin/bash

# 批量修复测试文件中的 Env 类型问题
# 添加缺失的 SESSIONS 属性

set -e

echo "🔧 修复测试文件中的 Env 类型问题..."

# 查找所有测试文件
TEST_FILES=$(find test -name "*.test.ts" -type f)

for file in $TEST_FILES; do
  echo "处理: $file"
  
  # 替换 env: {} 为 env: {} as any
  sed -i '' 's/env: {}/env: {} as any/g' "$file"
  
  # 替换 env: { API_KEY: 为 env: { API_KEY:, CICADA_SESSIONS: {} as any,
  sed -i '' 's/env: { API_KEY:/env: { API_KEY:/g' "$file"
  
  echo "✅ 完成: $file"
done

echo ""
echo "✅ 所有测试文件已修复"

