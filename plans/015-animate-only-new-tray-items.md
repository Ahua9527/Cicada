# 015 — Animate only newly inserted tray items

- **Status**: TODO
- **Commit**: f1f4588 + current 001–010 worktree
- **Severity**: P1
- **Category**: Motion semantics; state continuity

## Planned change

Add an internal, non-persisted `TrayEntryAnimationQueue`. Register new IDs before publishing inserted items and consume each ID after its first presentation. Existing and reopened items start visible; genuinely new items retain plan 005’s entry animation.

## Boundaries

- Preserve scale 0.96 + opacity, 0.20-second ease-out, maximum 0.20-second stagger, Reduce Motion opacity fallback, and removal poof.
- Do not delay persistence or interaction.

## Verification

- Reopening a populated Notch does not replay entry motion.
- Each new batch animates once and remains interactive immediately.
