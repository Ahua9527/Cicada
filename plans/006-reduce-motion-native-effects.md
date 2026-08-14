# 006 — Respect Reduce Motion in native effects

- **Status**: IMPLEMENTED — verification pending
- **Commit**: f1f4588
- **Severity**: MEDIUM
- **Category**: Accessibility; performance

## Applied change

`apps/agent/native/sentinel-app/Sentry/SentryView.swift` reads `accessibilityReduceMotion` and supplies ColorfulX with `speed: 0` in that mode, retaining the static sunset composition; normal mode remains speed `1`.

`apps/agent/native/sentinel-app/Sentry/NotchDrop/TrayDrop+View.swift` disables the repeating 1.5-second Pow glow under Reduce Motion and substitutes a static blue loading background.

## Verification

- Enable macOS Reduce Motion during an alert and during file import.
- The sunset and loading indication remain visible, but neither continuously moves.
