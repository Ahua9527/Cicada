#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
APP_ROOT="$REPO_ROOT/apps/agent/native/sentinel-app"
SENTRY_NOTICE="$APP_ROOT/ThirdParty/Sentry/VENDOR.md"
NOTCHDROP_NOTICE="$APP_ROOT/ThirdParty/NotchDrop/VENDOR.md"
SENTRY_COMMIT="7961a0365f39d1e72ba4e587c79f6ef147fd613e"
NOTCHDROP_TAG="2.9.26"
NOTCHDROP_COMMIT="b4ddec566169ea78ea0e1616f3e500228c19d8f7"

fail() {
  echo "vendor audit: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: ${1#$REPO_ROOT/}"
}

require_text() {
  grep -Fq -- "$2" "$1" || fail "missing '$2' in ${1#$REPO_ROOT/}"
}

check_local() {
  require_file "$SENTRY_NOTICE"
  require_file "$NOTCHDROP_NOTICE"
  require_file "$APP_ROOT/LICENSE"
  require_file "$APP_ROOT/ThirdParty/NotchDrop/LICENSE"
  require_file "$APP_ROOT/Sentry.xcodeproj/project.pbxproj"
  require_file "$APP_ROOT/Sentry/Sentry.swift"
  require_file "$APP_ROOT/Sentry/NotchDrop/NotchView.swift"

  require_text "$SENTRY_NOTICE" "Source: https://github.com/Ahua9527/Sentry"
  require_text "$SENTRY_NOTICE" "Baseline commit: $SENTRY_COMMIT"
  require_text "$SENTRY_NOTICE" 'Upstream `Sentry/` is integrated into `../../Sentry/`'
  require_text "$NOTCHDROP_NOTICE" "Source: https://github.com/Lakr233/NotchDrop"
  require_text "$NOTCHDROP_NOTICE" "Version: tag $NOTCHDROP_TAG"
  require_text "$NOTCHDROP_NOTICE" "Baseline commit: $NOTCHDROP_COMMIT"
  require_text "$NOTCHDROP_NOTICE" 'Upstream `NotchDrop/*.swift` is selectively integrated into `../../Sentry/NotchDrop/`'
  require_text "$APP_ROOT/LICENSE" "MIT License"
  require_text "$APP_ROOT/ThirdParty/NotchDrop/LICENSE" "MIT License"
  require_text "$APP_ROOT/Sentry.xcodeproj/project.pbxproj" "PBXFileSystemSynchronizedRootGroup"
  require_text "$APP_ROOT/Sentry.xcodeproj/project.pbxproj" "path = Sentry;"

  local sentry_swift_count notchdrop_swift_count
  sentry_swift_count="$(find "$APP_ROOT/Sentry" -maxdepth 1 -type f -name '*.swift' | wc -l | tr -d ' ')"
  notchdrop_swift_count="$(find "$APP_ROOT/Sentry/NotchDrop" -type f -name '*.swift' | wc -l | tr -d ' ')"
  [[ "$sentry_swift_count" -gt 0 ]] || fail "integrated Sentry source is empty"
  [[ "$notchdrop_swift_count" -gt 0 ]] || fail "integrated NotchDrop source is empty"

  echo "vendor audit: local provenance and source mappings are valid"
  echo "vendor audit: Sentry baseline $SENTRY_COMMIT ($sentry_swift_count top-level Swift files)"
  echo "vendor audit: NotchDrop $NOTCHDROP_TAG at $NOTCHDROP_COMMIT ($notchdrop_swift_count Swift files)"
}

clone_upstream() {
  local work_dir="$1"

  git clone --quiet --filter=blob:none https://github.com/Ahua9527/Sentry.git "$work_dir/Sentry"
  git -C "$work_dir/Sentry" -c advice.detachedHead=false checkout --quiet "$SENTRY_COMMIT"
  [[ "$(git -C "$work_dir/Sentry" rev-parse HEAD)" == "$SENTRY_COMMIT" ]] || fail "Sentry checkout does not match the pinned baseline"

  git -c advice.detachedHead=false clone --quiet --filter=blob:none --branch "$NOTCHDROP_TAG" --single-branch https://github.com/Lakr233/NotchDrop.git "$work_dir/NotchDrop"
  [[ "$(git -C "$work_dir/NotchDrop" rev-parse HEAD)" == "$NOTCHDROP_COMMIT" ]] || fail "NotchDrop tag does not match the pinned baseline"
}

emit_diff() {
  local vendor="$1"
  local work_dir diff_status
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/cicada-vendor-audit.XXXXXX")"
  trap "rm -rf '$work_dir'" EXIT
  clone_upstream "$work_dir"

  if [[ "$vendor" == "sentry" ]]; then
    cp -R "$APP_ROOT/Sentry" "$work_dir/CicadaSentry"
    rm -rf "$work_dir/CicadaSentry/NotchDrop"
  elif [[ "$vendor" == "notchdrop" ]]; then
    cp -R "$APP_ROOT/Sentry/NotchDrop" "$work_dir/CicadaNotchDrop"
  else
    fail "unknown vendor '$vendor' (expected sentry or notchdrop)"
  fi

  set +e
  if [[ "$vendor" == "sentry" ]]; then
    (cd "$work_dir" && git diff --no-index --src-prefix=upstream/ --dst-prefix=cicada/ Sentry/Sentry CicadaSentry)
    diff_status=$?
  else
    (cd "$work_dir" && git diff --no-index --src-prefix=upstream/ --dst-prefix=cicada/ NotchDrop/NotchDrop CicadaNotchDrop)
    diff_status=$?
  fi
  set -e

  [[ "$diff_status" -le 1 ]] || fail "diff failed with status $diff_status"
}

if [[ $# -eq 0 ]]; then
  check_local
  exit 0
fi

if [[ "$1" == "--diff" && $# -eq 2 ]]; then
  check_local >&2
  emit_diff "$2"
  exit 0
fi

fail "usage: $0 [--diff sentry|notchdrop]"
