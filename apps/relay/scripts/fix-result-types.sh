#!/bin/bash

# 批量修复测试文件中的 Result 类型使用
# 将 .ok/.value/.error 替换为 .success/.data/.error

set -e

echo "🔧 修复测试文件中的 Result 类型使用..."

# 查找所有测试文件
TEST_FILES=$(find test -name "*.test.ts" -type f)

for file in $TEST_FILES; do
  echo "处理: $file"

  # 替换 .ok 为 .success (但保留 mockResolvedValue 中的 ok 属性)
  # 替换 result.ok 为 result.success
  sed -i '' 's/result\.ok/result.success/g' "$file"
  sed -i '' 's/!result\.success/!result.success/g' "$file"

  # 替换 .value 为 .data
  sed -i '' 's/result\.value/result.data/g' "$file"

  # 替换 mockResolvedValue 中的 { ok: 为 { success:
  sed -i '' 's/{ ok:/{ success:/g' "$file"
  sed -i '' 's/{ok:/{success:/g' "$file"
  sed -i '' 's/, ok:/, success:/g' "$file"

  # 替换 mockResolvedValue 中的 value: 为 data:
  sed -i '' 's/{ success: true, value:/{ success: true, data:/g' "$file"
  sed -i '' 's/{ success: false, value:/{ success: false, data:/g' "$file"
  sed -i '' 's/, value:/, data:/g' "$file"

  # 替换 ErrorSeverity.WARNING 为 ErrorSeverity.MEDIUM
  sed -i '' 's/ErrorSeverity\.WARNING/ErrorSeverity.MEDIUM/g' "$file"

  # 替换 ErrorSeverity.ERROR 为 ErrorSeverity.HIGH
  sed -i '' 's/ErrorSeverity\.ERROR/ErrorSeverity.HIGH/g' "$file"

  echo "✅ 完成: $file"
done

echo ""
echo "✅ 所有测试文件已修复"

