# Animation implementation plans

These plans were created against commit `f1f4588`. Plans 001–003 and the source changes for 004–010 are in the current worktree; the 004–010 register remains TODO until its manual feel checks are complete.

| Order | Plan | Severity | Status | Depends on |
| --- | --- | --- | --- | --- |
| 1 | [001 — Require a hold before clearing the NotchDrop tray](001-hold-to-confirm-clear-notchdrop-tray.md) | HIGH | IMPLEMENTED — manual feel check pending | None |
| 2 | [002 — Animate Relay connection save feedback](002-animate-connection-save-feedback.md) | MEDIUM | IMPLEMENTED — manual feel check pending | None |
| 3 | [003 — Add restrained hover feedback to maintenance actions](003-add-folder-grid-hover-feedback.md) | LOW | IMPLEMENTED — manual feel check pending | 001 if it changes `FolderGridButton.swift` |
| 4 | [004 — Restore accessible tray-clear confirmation](004-accessible-tray-clear-confirmation.md) | HIGH | TODO | 001 |
| 5 | [005 — Smooth NotchDrop item entry](005-smooth-notchdrop-item-entry.md) | HIGH | TODO | None |
| 6 | [006 — Respect Reduce Motion in native effects](006-reduce-motion-native-effects.md) | MEDIUM | TODO | None |
| 7 | [007 — Refine NotchDrop file hover](007-refine-notchdrop-file-hover.md) | MEDIUM | TODO | 005 |
| 8 | [008 — Add accessible status semantics and Hero handoff](008-accessibility-semantics-and-hero-transition.md) | MEDIUM | TODO | None |
| 9 | [009 — Animate diagnostic strips](009-animate-diagnostic-strips.md) | LOW | TODO | None |
| 10 | [010 — Align Settings tab timing](010-align-settings-tab-timing.md) | LOW | TODO | None |
| 11 | [011 — Make settings controls accessible](011-accessible-settings-controls.md) | P0 | TODO | 008 |
| 12 | [012 — Await the real camera permission result](012-await-camera-permission-result.md) | P0 | TODO | 011 |
| 13 | [013 — Make NotchDrop actions immediate and reachable](013-direct-notchdrop-actions.md) | P0 | TODO | 005, 007 |
| 14 | [014 — Add consistent NotchDrop target feedback](014-notchdrop-target-feedback.md) | P1 | TODO | 013 |
| 15 | [015 — Animate only newly inserted tray items](015-animate-only-new-tray-items.md) | P1 | TODO | 005, 013 |
| 16 | [016 — Keep settings save feedback truthful](016-truthful-settings-save-feedback.md) | P1 | TODO | 002 |
| 17 | [017 — Make the Notch menu trigger explicit](017-explicit-notch-menu-trigger.md) | P1 | TODO | 013 |
| 18 | [018 — Present help as contextual popovers](018-contextual-help-popovers.md) | P2 | TODO | 011 |
| 19 | [019 — Add menu-bar hover feedback](019-menubar-hover-feedback.md) | P2 | TODO | None |

Recommended execution order is 001 → 002 → 003 → 004 → 006 → 005 → 007 → 008 → 009 → 010. Plan 004 corrects the accessibility path introduced by 001; plan 007 layers on the item-entry work in 005 without changing the panel spring.

The interaction follow-up order is 011 → 012 → 013 → 014 → 015 → 016 → 017 → 018 → 019. Plan 013 supersedes only plan 007's Option-icon panel animation; plan 015 corrects plan 005 so persisted items do not replay insertion motion.

All plans require a macOS manual feel check in addition to the existing agent test and build commands. If the implementation checkout has moved from `f1f4588`, reconcile the cited code before editing rather than applying a plan mechanically.
