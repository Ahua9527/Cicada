# 018 — Present help as contextual popovers

- **Status**: TODO
- **Commit**: f1f4588 + current 001–010 worktree
- **Severity**: P2
- **Category**: Progressive disclosure; spatial continuity

## Planned change

Anchor the existing Help content to each pane’s Help button using the system macOS popover. Outside click and Escape dismiss it and return focus to the trigger.

## Boundaries

- Use only the system popover transition; do not add custom springs, scale, or blur.
- Preserve Help content and localization.

## Verification

- Overview, Settings, and Maintenance help opens beside the triggering button and dismisses normally.
- Keyboard and VoiceOver can open and close it.
