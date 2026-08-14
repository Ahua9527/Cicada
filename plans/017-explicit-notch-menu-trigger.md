# 017 — Make the Notch menu trigger explicit

- **Status**: TODO
- **Commit**: f1f4588 + current 001–010 worktree
- **Severity**: P1
- **Category**: Discoverability; keyboard accessibility

## Planned change

Add a source-compatible `onShowMenu` closure to `NotchPanel` and turn both visible header icons into real buttons. Use explicit `showMenu` and `dismissNotification` model actions, then remove the broad global headline hit region.

## Boundaries

- Do not change `NotchDropDelegate` or the P4 content transition.
- Keep the existing notification-to-normal behavior.

## Verification

- The visible icon, keyboard focus, and VoiceOver all invoke the same action.
- Clicking unrelated header space no longer changes content.
