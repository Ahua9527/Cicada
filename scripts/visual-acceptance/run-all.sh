#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"
status=0
gui_ready=0

log() {
  printf '[visual-acceptance] %s\n' "$*"
}

mkdir -p "$OUTPUT_DIR/app" "$OUTPUT_DIR/design" "$OUTPUT_DIR/compare"
rm -f "$OUTPUT_DIR/app"/*.png "$OUTPUT_DIR/compare"/*.png

log "1/4 构建并启动 Cicada"
if "$SCRIPT_DIR/build-and-run.sh"; then
  gui_ready=1
else
  status=1
  log "构建/GUI 启动失败；继续生成设计稿与阻塞报告"
fi

log "2/4 截取 app 画面"
if (( gui_ready == 1 )); then
  if ! "$SCRIPT_DIR/capture.sh"; then
    status=1
    log "App 截图失败；继续生成其余产物"
  fi
else
  log "跳过 app 截图"
fi

log "3/4 截取设计稿"
if ! "$SCRIPT_DIR/capture-design.sh"; then
  status=1
  log "设计稿截图失败"
fi

log "4/4 生成对比图与报告"
if ! python3 "$SCRIPT_DIR/compare.py" --allow-missing; then
  status=1
  log "对比报告生成失败"
fi

for kind in app design compare; do
  count="$(find "$OUTPUT_DIR/$kind" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')"
  log "$kind PNG：$count/4"
  [[ "$count" == "4" ]] || status=1
done

if (( status != 0 )); then
  log "验收链路未完整通过；请查看 $SCRIPT_DIR/ACCEPTANCE_REPORT.md"
  exit 1
fi

log "验收产物已完成：$SCRIPT_DIR/ACCEPTANCE_REPORT.md"

