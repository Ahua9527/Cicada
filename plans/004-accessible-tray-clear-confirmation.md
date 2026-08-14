# 004 — Restore accessible tray-clear confirmation

- **Status**: IMPLEMENTED — verification pending
- **Commit**: f1f4588
- **Severity**: HIGH
- **Category**: Accessibility; destructive-action feedback

## Applied change

`apps/agent/swift/Sources/CicadaUI/Components/HoldToConfirmButton.swift` keeps the existing 2.0-second pointer hold and 0.2-second reset. A focusable SwiftUI `Button` now opens a system confirmation alert for keyboard and VoiceOver activation, while a transparent, accessibility-hidden overlay owns pointer long-press input. The destructive alert action invokes the existing closure once; cancel does nothing.

`apps/agent/swift/Sources/CicadaUI/Resources/Localizable.xcstrings` now contains Chinese and English alert, hint, and cancel copy.

## Boundaries

- Do not change `FolderAction`, `clearTray()`, file deletion, or the 2.0-second safety hold.
- A pointer short click must not clear files or show the accessibility dialog.

## Verification

- Short-click, cancelled hold, and completed hold from both Notch and Maintenance controls.
- Keyboard Return/Space and VoiceOver activation must show the standard confirmation dialog; only its destructive action clears files.
