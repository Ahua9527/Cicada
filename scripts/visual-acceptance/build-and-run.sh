#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_DIR="$REPO_ROOT/apps/agent/native/sentinel-app"
PROJECT_PATH="$PROJECT_DIR/Sentry.xcodeproj"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="$PROJECT_DIR/.build/VisualAcceptanceDerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/Cicada.app"
PROCESS_NAME="Cicada"
WINDOW_WIDTH="${VISUAL_WINDOW_WIDTH:-900}"
WINDOW_HEIGHT="${VISUAL_WINDOW_HEIGHT:-638}"
TIMEOUT="${VISUAL_TIMEOUT:-30}"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

log() {
  printf '[visual-acceptance] %s\n' "$*"
}

die() {
  printf '[visual-acceptance] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

wait_for_process() {
  local expected="$1"
  local elapsed=0
  while (( elapsed < TIMEOUT * 4 )); do
    if [[ "$expected" == "running" ]] && pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
      return 0
    fi
    if [[ "$expected" == "stopped" ]] && ! pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
    ((elapsed += 1))
  done
  return 1
}

click_control_center_menu() {
  /usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
    if UI elements enabled is false then error "Accessibility permission is disabled"
    tell application process "Cicada"
        set frontmost to true
        set wantedNames to {"Open Control Center", "打开控制中心", "Control Center...", "Control Center…", "控制中心...", "控制中心…", "Overview", "概览"}
        repeat with menuBarItemRef in menu bar items of menu bar 1
            try
                repeat with menuItemRef in menu items of menu 1 of menuBarItemRef
                    if (name of menuItemRef as text) is in wantedNames then
                        click menuItemRef
                        return "clicked"
                    end if
                end repeat
            end try
        end repeat
    end tell
end tell
error "Control Center menu item was not found"
APPLESCRIPT
}

main_window_info() {
  /usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
    tell application process "Cicada"
        set targetWindow to missing value
        repeat with windowRef in windows
            try
                set windowSize to size of windowRef
                if (item 1 of windowSize) >= 600 and (item 2 of windowSize) >= 400 and (value of attribute "AXMain" of windowRef) is true then
                    set targetWindow to windowRef
                    exit repeat
                end if
            end try
        end repeat
        if targetWindow is missing value then
            repeat with windowRef in windows
                try
                    set windowSize to size of windowRef
                    if (item 1 of windowSize) >= 600 and (item 2 of windowSize) >= 400 then
                        set targetWindow to windowRef
                        exit repeat
                    end if
                end try
            end repeat
        end if
        if targetWindow is not missing value then
            set windowPosition to position of targetWindow
            set windowSize to size of targetWindow
            return "0," & (item 1 of windowPosition as text) & "," & (item 2 of windowPosition as text) & "," & (item 1 of windowSize as text) & "," & (item 2 of windowSize as text)
        end if
    end tell
end tell
error "Main window is not ready"
APPLESCRIPT
}

resize_main_window() {
  /usr/bin/osascript - "$WINDOW_WIDTH" "$WINDOW_HEIGHT" <<'APPLESCRIPT'
on run argv
    set requestedWidth to item 1 of argv as integer
    set requestedHeight to item 2 of argv as integer
    tell application "Finder" to set desktopBounds to bounds of window of desktop
    set screenWidth to item 3 of desktopBounds
    set screenHeight to item 4 of desktopBounds
    set targetX to (screenWidth - requestedWidth) div 2
    set targetY to (screenHeight - requestedHeight) div 2
    tell application "System Events"
        tell application process "Cicada"
            set targetWindow to missing value
            repeat with windowRef in windows
                try
                    set windowSize to size of windowRef
                    if (item 1 of windowSize) >= 600 and (item 2 of windowSize) >= 400 and (value of attribute "AXMain" of windowRef) is true then
                        set targetWindow to windowRef
                        exit repeat
                    end if
                end try
            end repeat
            if targetWindow is not missing value then
                set size of targetWindow to {requestedWidth, requestedHeight}
                set position of targetWindow to {targetX, targetY}
                perform action "AXRaise" of targetWindow
                return "resized"
            end if
        end tell
    end tell
    error "Main window could not be resized"
end run
APPLESCRIPT
}

require_command xcodebuild
require_command open
require_command osascript
require_command pgrep

[[ -d "$DEVELOPER_DIR" ]] || die "DEVELOPER_DIR 不存在：$DEVELOPER_DIR"
[[ -d "$PROJECT_PATH" ]] || die "找不到 Xcode 工程：$PROJECT_PATH"

log "构建 Sentry scheme（产物 Cicada.app，${CONFIGURATION}）"
xcodebuild \
  -quiet \
  -project "$PROJECT_PATH" \
  -scheme Sentry \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build

[[ -d "$APP_PATH" ]] || die "构建完成但找不到 app：$APP_PATH"
log "Xcode 构建成功"

if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
  log "退出旧 Cicada 实例"
  /usr/bin/osascript -e 'tell application "Cicada" to quit' >/dev/null 2>&1 || true
  wait_for_process stopped || die "旧 Cicada 实例未在 ${TIMEOUT}s 内退出"
fi

log "启动 $APP_PATH"
/usr/bin/open -n "$APP_PATH"
wait_for_process running || die "Cicada 未在 ${TIMEOUT}s 内启动"

if [[ "$(/usr/bin/osascript -e 'tell application "System Events" to return UI elements enabled' 2>/dev/null || true)" != "true" ]]; then
  die "缺少辅助功能权限。请在 系统设置 → 隐私与安全性 → 辅助功能 中允许当前终端/Codex，然后重跑。"
fi

log "打开控制中心并等待主窗口"
menu_ready=0
for ((attempt = 0; attempt < TIMEOUT * 4; attempt += 1)); do
  if click_control_center_menu >/dev/null 2>&1; then
    menu_ready=1
    break
  fi
  sleep 0.25
done
if (( menu_ready == 0 )); then
  click_control_center_menu >/dev/null
  die "Cicada 应用菜单未在 ${TIMEOUT}s 内就绪"
fi
window_ready=0
for ((attempt = 0; attempt < TIMEOUT * 4; attempt += 1)); do
  if main_window_info >/dev/null 2>&1; then
    window_ready=1
    break
  fi
  sleep 0.25
done
(( window_ready == 1 )) || die "主窗口未在 ${TIMEOUT}s 内出现；请确认 Cicada 菜单可由辅助功能控制。"

resize_main_window >/dev/null
sleep 0.5
log "Cicada 已就绪：窗口 ${WINDOW_WIDTH}×${WINDOW_HEIGHT} pt"
