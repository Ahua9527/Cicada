# 016 — Keep settings save feedback truthful

- **Status**: TODO
- **Commit**: f1f4588 + current 001–010 worktree
- **Severity**: P1
- **Category**: Error feedback; state accuracy

## Planned change

Clear Relay save feedback as soon as the address changes. Surface persistent Sentry auto-save errors in Settings with a Retry action backed by an internal `ConfigModel` retry method. Do not show the 150ms saving phase or repeated success messages.

Errors enter with the existing 0.20-second opacity + top transition, falling back to opacity under Reduce Motion.

## Boundaries

- Preserve debounce, atomic persistence, and connection merge behavior.
- Build on plan 002 without changing network configuration contracts.

## Verification

- Editing a saved Relay URL removes the stale success message.
- A forced Sentry write failure remains visible; Retry clears it only after a successful write.
