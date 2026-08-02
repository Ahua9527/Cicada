#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DESIGN_HTML="$REPO_ROOT/design-previews/2026-07-15-cicada-redesign/index.html"
APP_DIR="$SCRIPT_DIR/output/app"
OUTPUT_DIR="$SCRIPT_DIR/output/design"
POINT_WIDTH="${VISUAL_WINDOW_WIDTH:-900}"
POINT_HEIGHT="${VISUAL_WINDOW_HEIGHT:-638}"
DEFAULT_SCALE="${VISUAL_SCALE:-2}"
CHROME_TIMEOUT="${VISUAL_CHROME_TIMEOUT:-15}"

log() {
  printf '[visual-acceptance] %s\n' "$*"
}

die() {
  printf '[visual-acceptance] ERROR: %s\n' "$*" >&2
  exit 1
}

find_chrome() {
  if [[ -n "${CHROME_BIN:-}" && -x "$CHROME_BIN" ]]; then
    printf '%s\n' "$CHROME_BIN"
    return 0
  fi
  local candidate
  for candidate in \
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \
    '/Applications/Chromium.app/Contents/MacOS/Chromium' \
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

png_dimensions() {
  python3 - "$1" <<'PY'
from PIL import Image
import sys
with Image.open(sys.argv[1]) as image:
    print(f"{image.width},{image.height}")
PY
}

validate_png() {
  python3 - "$1" <<'PY'
from pathlib import Path
from PIL import Image
import sys
path = Path(sys.argv[1])
if not path.is_file() or path.stat().st_size == 0:
    raise SystemExit(f"missing or empty PNG: {path}")
with Image.open(path) as image:
    image.verify()
with Image.open(path) as image:
    print(f"{path.name}: {image.width}x{image.height}")
PY
}

render_screen() {
  local screen="$1"
  local selector="$2"
  local app_png="$APP_DIR/$screen.png"
  local point_width="$POINT_WIDTH"
  local point_height="$POINT_HEIGHT"
  local scale="$DEFAULT_SCALE"
  local pixel_width pixel_height dimensions

  if [[ -f "$app_png" ]]; then
    dimensions="$(png_dimensions "$app_png")"
    IFS=',' read -r pixel_width pixel_height <<<"$dimensions"
    if [[ "$screen" == "menubar" ]]; then
      point_width="$(python3 -c "print(max(1, round($pixel_width / $DEFAULT_SCALE)))")"
      point_height="$(python3 -c "print(max(1, round($pixel_height / $DEFAULT_SCALE)))")"
      scale="$DEFAULT_SCALE"
    else
      scale="$(python3 -c "print(max(1.0, min(4.0, $pixel_width / $POINT_WIDTH)))")"
      point_height="$(python3 -c "print(max(1, round($pixel_height / $scale)))")"
    fi
  elif [[ "$screen" == "menubar" ]]; then
    point_width=320
    point_height=340
  fi

  local temp_html="$TMP_DIR/$screen.html"
  python3 - "$DESIGN_HTML" "$temp_html" "$selector" "$screen" <<'PY'
from pathlib import Path
import sys

source, destination, selector, screen = sys.argv[1:]
html = Path(source).read_text(encoding="utf-8")
injection = f"""
<style id="visual-acceptance-crop">
html, body {{ width:100%; height:100%; overflow:hidden; background:#09090B; }}
body {{ margin:0; padding:0; }}
</style>
<script>
(() => {{
  const target = document.querySelector({selector!r});
  if (!target) {{
    document.body.textContent = 'Missing design selector: ' + {selector!r};
    return;
  }}
  document.body.replaceChildren(target);
  Object.assign(target.style, {{
    width: '100vw',
    height: '100vh',
    minHeight: '0',
    margin: '0',
    padding: {"'0'" if screen != "menubar" else "'0'"},
    borderRadius: '0',
    boxSizing: 'border-box'
  }});
  if ({screen!r} !== 'menubar') {{
    const titlebar = target.querySelector('.mac-titlebar');
    const split = target.querySelector('.split-view');
    if (titlebar) titlebar.style.height = '38px';
    if (split) split.style.height = 'calc(100vh - 38px)';
  }} else {{
    const dropdown = target.querySelector('.menubar-dropdown');
    target.style.width = '320px';
    if (dropdown) {{
      dropdown.style.right = 'auto';
      dropdown.style.left = '16px';
    }}
  }}
}})();
</script>
"""
if "</body>" not in html:
    raise SystemExit("design HTML has no </body>")
Path(destination).write_text(html.replace("</body>", injection + "\n</body>"), encoding="utf-8")
PY

  local output="$OUTPUT_DIR/$screen.png"
  log "渲染设计稿 ${screen}：${point_width}×${point_height} pt，scale=${scale}"
  "$CHROME" \
    --headless=new \
    --disable-gpu \
    --hide-scrollbars \
    --no-first-run \
    --no-default-browser-check \
    --allow-file-access-from-files \
    --force-device-scale-factor="$scale" \
    --window-size="$point_width,$point_height" \
    --virtual-time-budget=1000 \
    --user-data-dir="$TMP_DIR/chrome-$screen" \
    --screenshot="$output" \
    "file://$temp_html" >/dev/null 2>&1 &
  local chrome_pid=$!
  local screenshot_ready=0
  for ((attempt = 0; attempt < CHROME_TIMEOUT * 10; attempt += 1)); do
    if [[ -s "$output" ]]; then
      sleep 0.25
      screenshot_ready=1
      break
    fi
    if ! kill -0 "$chrome_pid" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
  if kill -0 "$chrome_pid" >/dev/null 2>&1; then
    kill -INT "$chrome_pid" >/dev/null 2>&1 || true
  fi
  wait "$chrome_pid" >/dev/null 2>&1 || true
  (( screenshot_ready == 1 )) || die "Chrome 未在 ${CHROME_TIMEOUT}s 内生成 $screen 截图"
  validate_png "$output"
}

command -v python3 >/dev/null 2>&1 || die "缺少 python3"
python3 -c 'import PIL' >/dev/null 2>&1 || die "缺少 Pillow：python3 无法 import PIL"
[[ -f "$DESIGN_HTML" ]] || die "找不到设计稿：$DESIGN_HTML"
CHROME="$(find_chrome)" || die "未找到 Chrome/Chromium/Edge；可通过 CHROME_BIN 指定可执行文件"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.png
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cicada-visual-design.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

render_screen overview '#screen-overview .mockup-frame'
render_screen settings '#screen-settings .mockup-frame'
render_screen maintenance '#screen-maintenance .mockup-frame'
render_screen menubar '#screen-menubar .menubar-mockup'

log "设计稿截图完成：$OUTPUT_DIR"
