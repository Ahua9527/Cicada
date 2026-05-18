#!/bin/bash

# 批量修复 middleware.test.ts 中的 startTime 属性问题
# 将 startTime 替换为 timestamp

set -e

echo "🔧 修复 middleware.test.ts 中的 startTime 属性..."

FILE="test/unit/infrastructure/middleware.test.ts"

# 替换 startTime: 为 timestamp:
sed -i '' 's/startTime:/timestamp:/g' "$FILE"

echo "✅ 完成: $FILE"

