#!/bin/bash

# 批量修复测试文件中剩余的 mock 对象
# 将 mockResolvedValue({ ok: 替换为 mockResolvedValue({ success:

set -e

echo "🔧 修复测试文件中剩余的 mock 对象..."

# 查找所有测试文件
TEST_FILES=$(find test -name "*.test.ts" -type f)

for file in $TEST_FILES; do
  echo "处理: $file"
  
  # 替换 mockResolvedValue({ ok: 为 mockResolvedValue({ success:
  sed -i '' 's/mockResolvedValue({$/mockResolvedValue({/g' "$file"
  sed -i '' 's/^        ok: false,$/        success: false,/g' "$file"
  sed -i '' 's/^        ok: true,$/        success: true,/g' "$file"
  
  echo "✅ 完成: $file"
done

echo ""
echo "✅ 所有测试文件已修复"

