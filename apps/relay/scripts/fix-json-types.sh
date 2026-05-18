#!/bin/bash

# 批量修复测试文件中的 JSON 类型问题
# 将 await response.json() 添加 as any 类型断言

set -e

echo "🔧 修复测试文件中的 JSON 类型问题..."

# 查找所有测试文件
TEST_FILES=$(find test -name "*.test.ts" -type f)

for file in $TEST_FILES; do
  echo "处理: $file"
  
  # 替换 await response.json() 为 await response.json() as any
  sed -i '' 's/await response\.json()/await response.json() as any/g' "$file"
  sed -i '' 's/await request\.json()/await request.json() as any/g' "$file"
  
  echo "✅ 完成: $file"
done

echo ""
echo "✅ 所有测试文件已修复"

