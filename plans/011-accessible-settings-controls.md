# 011 — Make settings controls accessible

- **Status**: TODO
- **Commit**: f1f4588 + current 001–010 worktree
- **Severity**: P0
- **Category**: Accessibility; settings interaction

## Planned change

Associate every `SettingRow` title and description with its actual control while hiding the duplicate visible copy from the accessibility tree. Give `CicadaTextField` a real semantic label and hint, expose the selected trait on Settings tabs, and label the help icon as “Help”.

## Boundaries

- Do not change settings layout, focus order, persistence, or animation.
- Extend plan 008; do not alter its alarm, Hero, or readiness behavior.

## Verification

- VoiceOver announces each control name, value, hint, and selected Settings tab once.
- Pointer and keyboard settings behavior remains unchanged.
