#!/bin/bash

# 批量修复 middleware.test.ts 中缺少的 method 和 headers 属性

set -e

echo "🔧 修复 middleware.test.ts 中的 MiddlewareContext..."

FILE="test/unit/infrastructure/middleware.test.ts"

# 在 url, 后面添加 method 和 headers
sed -i '' 's/url,$/url,\n        method: '\''GET'\'',\n        headers: {},/g' "$FILE"

echo "✅ 完成: $FILE"

