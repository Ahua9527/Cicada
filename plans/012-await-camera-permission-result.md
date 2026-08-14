# 012 — Await the real camera permission result

- **Status**: TODO
- **Commit**: f1f4588 + current 001–010 worktree
- **Severity**: P0
- **Category**: Permission feedback; state accuracy

## Planned change

Change the host camera-permission injection to return `CameraAuthorizationStatus` asynchronously. `RecordingCard` starts in a neutral checking state, shows a waiting state while the system dialog is open, applies the real result immediately, and refreshes permission plus camera options when the app becomes active again.

State replacement is a 0.20-second opacity-only transition.

## Boundaries

- Do not change recording persistence or enable/disable policy.
- Do not retain the obsolete fire-and-forget permission signature.

## Verification

- Waiting more than one second in the system prompt still produces the correct final state.
- Returning from System Settings refreshes permission and device options.
