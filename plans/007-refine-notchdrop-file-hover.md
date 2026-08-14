# 007 — Refine NotchDrop file hover

- **Status**: IMPLEMENTED — verification pending
- **Commit**: f1f4588
- **Severity**: MEDIUM
- **Category**: Frequency; cohesion

## Applied change

`apps/agent/native/sentinel-app/Sentry/NotchDrop/TrayDrop+DropItemView.swift` gives only file-item hover a `1.02` scale and `easeOut(duration: 0.15)`. The panel’s 0.5-second interactive spring and the Option-key delete-icon animation remain unchanged.

## Verification

- Sweep rapidly across several file items; feedback should retarget quickly without the panel-opening bounce.
- Hold Option and confirm the delete icon retains its existing motion.
