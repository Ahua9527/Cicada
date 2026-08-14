# 014 — Add consistent NotchDrop target feedback

- **Status**: TODO
- **Commit**: f1f4588 + current 001–010 worktree
- **Severity**: P1
- **Category**: Drag feedback; cohesion

## Planned change

Use the tray’s existing `targeting` state to change its dashed border, subtle fill, icon, and text color. Align the AirDrop target with a 0.12-second ease-out color transition.

## Boundaries

- Do not scale, bounce, or change drop acceptance and persistence.
- Keep the same color-only feedback under Reduce Motion.

## Verification

- Both drop targets acknowledge entry immediately and return cleanly on exit.
- Dropping files still routes to the original destinations.
