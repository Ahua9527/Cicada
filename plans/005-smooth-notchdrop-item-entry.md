# 005 — Smooth NotchDrop item entry

- **Status**: IMPLEMENTED — verification pending
- **Commit**: f1f4588
- **Severity**: HIGH
- **Category**: Physicality; stagger

## Applied change

`apps/agent/native/sentinel-app/Sentry/NotchDrop/TrayDrop+DropItemView.swift` now drives each new file with local state from opacity `0` and scale `0.96` to identity using `easeOut(duration: 0.20)`. Index delays are `0.05 × min(index, 4)` seconds. Under Reduce Motion, only opacity changes. Existing `.movingParts.poof` removal remains.

`apps/agent/native/sentinel-app/Sentry/NotchDrop/TrayDrop+View.swift` enumerates the stable file IDs for the delay and no longer applies the panel spring to `tvm.items`.

## Boundaries

- Do not delay persistence, opening, dragging, or deletion.
- Do not modify the P4 `NotchContentView` 0.8 transition.

## Verification

- Import one and several files; all items must be interactive immediately and finish entering within 0.20 seconds.
- Confirm removal still uses the existing poof effect.
