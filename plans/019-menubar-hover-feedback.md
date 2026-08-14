# 019 — Add menu-bar hover feedback

- **Status**: TODO
- **Commit**: f1f4588 + current 001–010 worktree
- **Severity**: P2
- **Category**: Pointer feedback; polish

## Planned change

Give `MenuBarButtonStyle` view-local hover state. Hover uses a 0.10-second ease-out background-color transition; pressed feedback remains immediate and stronger.

## Boundaries

- Do not scale rows, change row height, or animate menu presentation.

## Verification

- Rapid pointer movement retargets cleanly with no lag or layout movement.
- Press and keyboard activation remain immediate.
