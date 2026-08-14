# 009 — Animate diagnostic strips

- **Status**: IMPLEMENTED — verification pending
- **Commit**: f1f4588
- **Severity**: LOW
- **Category**: State feedback; Reduce Motion

## Applied change

`Diagnostic.motionKey` in `apps/agent/swift/Sources/CicadaUI/Models/ReadinessItem.swift` is stable for a level/message pair. Overview and both Maintenance diagnostic outlets now use that key with a `0.20` second ease-out transition: opacity plus top-edge move normally, opacity only under Reduce Motion.

## Verification

- The same diagnostic returned by a later poll does not replay.
- A new or changed diagnostic enters once without layout jitter; Reduce Motion keeps the fade only.
