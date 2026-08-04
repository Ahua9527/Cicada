#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output/app"
PROCESS_NAME="Cicada"
TIMEOUT="${VISUAL_TIMEOUT:-30}"
WINDOW_WIDTH="${VISUAL_WINDOW_WIDTH:-900}"
WINDOW_HEIGHT="${VISUAL_WINDOW_HEIGHT:-638}"

log() {
  printf '[visual-acceptance] %s\n' "$*"
}

die() {
  printf '[visual-acceptance] ERROR: %s\n' "$*" >&2
  exit 1
}

validate_png() {
  local path="$1"
  python3 - "$path" <<'PY'
from pathlib import Path
import sys
from PIL import Image

path = Path(sys.argv[1])
if not path.is_file() or path.stat().st_size == 0:
    raise SystemExit(f"missing or empty PNG: {path}")
with Image.open(path) as image:
    image.verify()
with Image.open(path) as image:
    if image.width < 100 or image.height < 100:
        raise SystemExit(f"unexpected PNG size: {image.size}")
print(f"{path.name}: {image.width}x{image.height}")
PY
}

main_window_info() {
  /usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
    tell application process "Cicada"
        set frontmost to true
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
            perform action "AXRaise" of targetWindow
            set windowPosition to position of targetWindow
            set windowSize to size of targetWindow
            return "0," & (item 1 of windowPosition as text) & "," & (item 2 of windowPosition as text) & "," & (item 1 of windowSize as text) & "," & (item 2 of windowSize as text)
        end if
    end tell
end tell
error "Main window is not ready"
APPLESCRIPT
}

close_control_center_windows() {
  /usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
    tell application process "Cicada"
        repeat with windowRef in windows
            try
                set windowSize to size of windowRef
                if (item 1 of windowSize) >= 600 and (item 2 of windowSize) >= 400 then
                    perform action "AXClose" of windowRef
                end if
            end try
        end repeat
    end tell
end tell
APPLESCRIPT
}

resize_main_window() {
  /usr/bin/osascript - "$WINDOW_WIDTH" "$WINDOW_HEIGHT" <<'APPLESCRIPT'
on run argv
    set requestedWidth to item 1 of argv as integer
    set requestedHeight to item 2 of argv as integer
    tell application "Finder" to set desktopBounds to bounds of window of desktop
    set targetX to ((item 3 of desktopBounds) - requestedWidth) div 2
    set targetY to ((item 4 of desktopBounds) - requestedHeight) div 2
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
            if targetWindow is missing value then error "Main window not found"
            set size of targetWindow to {requestedWidth, requestedHeight}
            set position of targetWindow to {targetX, targetY}
            perform action "AXRaise" of targetWindow
        end tell
    end tell
end run
APPLESCRIPT
}

click_section_menu() {
  local section="$1"
  /usr/bin/osascript - "$section" <<'APPLESCRIPT'
on run argv
    set sectionName to item 1 of argv
    if sectionName is "overview" then
        set wantedNames to {"Overview", "概览", "Open Control Center", "打开控制中心"}
    else if sectionName is "settings" then
        set wantedNames to {"Settings", "设置"}
    else if sectionName is "maintenance" then
        set wantedNames to {"Maintenance", "维护"}
    else
        error "Unknown section: " & sectionName
    end if

    tell application "System Events"
        tell application process "Cicada"
            set frontmost to true
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
    error "Menu item not found for " & sectionName
end run
APPLESCRIPT
}

click_connection_tab() {
  /usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
    tell application process "Cicada"
        repeat with windowRef in windows
            try
                set windowSize to size of windowRef
                if (item 1 of windowSize) >= 600 and (item 2 of windowSize) >= 400 then
                    repeat with elementRef in entire contents of windowRef
                        try
                            if role of elementRef is "AXButton" and (name of elementRef as text) is in {"连接", "Connection"} then
                                click elementRef
                                return "clicked"
                            end if
                        end try
                    end repeat
                end if
            end try
        end repeat
    end tell
end tell
return "not-found"
APPLESCRIPT
}

capture_main_window() {
  local output="$1"
  local info window_id x y width height
  info="$(main_window_info)"
  IFS=',' read -r window_id x y width height <<<"$info"
  /usr/sbin/screencapture -x -R"$x,$y,$width,$height" "$output"
  validate_png "$output"
}

capture_menu_bar() {
  local output="$1"
  /usr/bin/osascript - "$output" <<'APPLESCRIPT'
on run argv
set outputPath to item 1 of argv
tell application "System Events"
    key code 53
    delay 0.1
    tell application process "Cicada"
        set statusItem to missing value
        try
            if (count of menu bars) >= 2 and (count of menu bar items of menu bar 2) > 0 then
                set statusItem to menu bar item 1 of menu bar 2
            end if
        end try
        if statusItem is missing value then
            repeat with menuBarRef in menu bars
                repeat with itemRef in menu bar items of menuBarRef
                    try
                        set itemDescription to description of itemRef as text
                        if itemDescription contains "status" or itemDescription contains "menu extra" then
                            set statusItem to itemRef
                            exit repeat
                        end if
                    end try
                end repeat
                if statusItem is not missing value then exit repeat
            end repeat
        end if
        if statusItem is missing value then error "MenuBarExtra status item not found"

        set itemPosition to position of statusItem
        set regionLeft to (item 1 of itemPosition) - 64
        if regionLeft < 0 then set regionLeft to 0
        click statusItem
        delay 0.3
        do shell script "/usr/sbin/screencapture -x -R" & regionLeft & ",0,320,340 " & quoted form of outputPath
        key code 53
        return regionLeft as text
    end tell
end tell
end run
APPLESCRIPT
}

command -v osascript >/dev/null 2>&1 || die "缺少 osascript"
command -v screencapture >/dev/null 2>&1 || die "缺少 screencapture"
command -v python3 >/dev/null 2>&1 || die "缺少 python3"
python3 -c 'import PIL' >/dev/null 2>&1 || die "缺少 Pillow：python3 无法 import PIL"
pgrep -x "$PROCESS_NAME" >/dev/null 2>&1 || die "Cicada 未运行；请先执行 build-and-run.sh"

if [[ "$(/usr/bin/osascript -e 'tell application "System Events" to return UI elements enabled' 2>/dev/null || true)" != "true" ]]; then
  die "缺少辅助功能权限。请在 系统设置 → 隐私与安全性 → 辅助功能 中授权当前终端/Codex。"
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.png

for section in overview settings maintenance; do
  log "切换并截取 $section"
  close_control_center_windows >/dev/null 2>&1 || true
  sleep 0.2
  click_section_menu "$section" >/dev/null
  sleep 0.5
  resize_main_window >/dev/null
  sleep 0.5
  if [[ "$section" == "settings" ]]; then
    tab_result="$(click_connection_tab)"
    [[ "$tab_result" == "clicked" ]] || log "警告：未定位到连接 Tab；继续截取当前 settings 状态"
    sleep 0.4
  fi
  capture_main_window "$OUTPUT_DIR/$section.png"
done

log "展开并截取 MenuBarExtra"
capture_menu_bar "$OUTPUT_DIR/menubar.png" >/dev/null
validate_png "$OUTPUT_DIR/menubar.png"

log "App 截图完成：$OUTPUT_DIR"
