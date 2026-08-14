# 010 — Align Settings tab timing

- **Status**: IMPLEMENTED — verification pending
- **Commit**: f1f4588
- **Severity**: LOW
- **Category**: Cohesion

## Applied change

`apps/agent/swift/Sources/CicadaUI/Views/SettingsPane.swift` now changes settings tabs with `easeInOut(duration: 0.20)`, matching `docs/Design.md`. The existing opacity content transition and all layout/navigation behavior remain unchanged.

## Verification

- Switch each tab repeatedly; content should crossfade in 200 ms with no scroll-position, sidebar, or geometry animation.
