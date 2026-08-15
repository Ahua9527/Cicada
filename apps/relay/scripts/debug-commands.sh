#!/bin/bash
# 全命令遍历调试：把共享契约 COMMANDS 里的命令逐个经 relay 打到本机 daemon 并记录结果。
# 用法：CICADA_SC_TOKEN=<token> bash apps/relay/scripts/debug-commands.sh [命令白名单(逗号分隔)]
# 要求：wrangler dev 在 127.0.0.1:8787 运行、daemon 已连接、cicada shortcut create 生成授权 token。
# 危险命令（sleep/restart/shutdown）默认不在遍历范围，需显式列入白名单才会执行。

set -uo pipefail

RELAY_URL="${CICADA_RELAY_URL:-http://127.0.0.1:8787}"
DEVICE_ID="${CICADA_DEVICE_ID:-MAC_2C501BC5B5D74431ADB19AFE30CD9CD3}"
TOKEN="${CICADA_SC_TOKEN:?需要 CICADA_SC_TOKEN（cicada shortcut create 输出）}"

fire() {
  local cmd="$1" params="${2:-}"
  local body="{\"device_id\":\"$DEVICE_ID\",\"command\":\"$cmd\",\"request_id\":\"traversal-$cmd-$RANDOM\""
  [ -n "$params" ] && body="$body,\"params\":$params"
  body="$body}"
  local resp
  resp=$(curl -s -m 20 -X POST "$RELAY_URL/v1/shortcuts/command" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$body")
  python3 - "$resp" "$cmd" <<'PY'
import json, sys
resp, cmd = sys.argv[1], sys.argv[2]
try:
    d = json.loads(resp)
    ok, succ = d.get("ok"), d.get("success")
    msg = (d.get("message") or d.get("error") or "")[:110]
    print(("PASS" if ok and succ else "FAIL") + " | " + cmd + " | " + msg)
except Exception:
    print("FAIL | " + cmd + " | 响应解析失败: " + resp[:120])
PY
  sleep 1
}

WHITELIST="${1:-}"
run() {  # run <cmd> [params-json]
  if [ -z "$WHITELIST" ] || [[ ",$WHITELIST," == *",$1,"* ]]; then fire "$1" "${2:-}"; fi
}

echo "== A. 只读/无害"
run ping; run status; run bt_status; run app_list; run sentry_status; run screenshot; run wake

echo "== B. 状态切换（含恢复）"
run caffeinate; run decaffeinate
run mute; run unmute
run volume_set '{"level":0.3}'; run volume_up; run volume_down
run brightness_set '{"level":0.5}'; run brightness_up; run brightness_down

echo "== C. 蓝牙（预期优雅失败：未授权）"
run bt_on; run bt_off; run bt_toggle

echo "== D. 应用控制（Calculator 短暂开合）"
run app_open '{"name":"Calculator"}'; run app_switch '{"name":"Calculator"}'; run app_close '{"name":"Calculator"}'

echo "== E. 安防模式（开后即停）"
run sentry_start; run sentry_status; run sentry_open; run sentry_unlock; run sentry_stop

echo "== F. 会话级（最后执行；sleep/restart/shutdown 需显式白名单）"
run sleep_displays
run lock
run sleep
run restart
run shutdown

echo "== 遍历完成"
