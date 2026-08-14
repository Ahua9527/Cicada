# 013 — Make NotchDrop actions immediate and reachable

- **Status**: TODO
- **Commit**: f1f4588 + current 001–010 worktree
- **Severity**: P0
- **Category**: Direct interaction; accessibility

## Planned change

Use standard buttons for the AirDrop click target and stored-file activation while retaining file drag. Close the Notch and schedule file opening, the picker, or AirDrop on the next main-loop turn instead of fixed 0.25/0.5-second delays.

Keep pointer deletion behind Option. The delete affordance becomes a real, explicitly hit-tested button; the file card exposes a VoiceOver delete action. Option feedback is immediate and no longer reuses the panel spring.

## Boundaries

- Preserve the stored-file deletion implementation, removal poof, file hover, and original source file.
- Supersede only plan 007’s requirement that the Option icon retain the panel animation.

## Verification

- File opening and the picker respond immediately without breaking drag.
- Hidden delete controls never accept pointer input; Option and VoiceOver each delete once.
