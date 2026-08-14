# 001 — Require a hold before clearing the NotchDrop tray

- **Status**: IMPLEMENTED — manual feel check pending
- **Commit**: f1f4588
- **Severity**: HIGH
- **Category**: Purpose & frequency; feedback; accessibility
- **Estimated scope**: 5–7 Swift files, plus focused tests

## Problem

Two visible controls delete every saved NotchDrop tray file after one click. This is destructive: `TrayDrop.removeAll()` calls `delete(item:)`, which calls `FileManager.default.removeItem(at:)`.

```swift
// apps/agent/swift/Sources/CicadaUI/Views/NotchDrop/NotchMenu.swift:46-48 — current
menuButton(icon: "trash", label: String(localized: "清空", bundle: .module), tint: .cicadaDanger) {
    delegate.clearTray()
}

// apps/agent/native/sentinel-app/Sentry/NotchDrop/TrayDrop.swift:116-118 — current
func removeAll() {
    items.forEach { delete(item: $0) }
}
```

The host also exposes the same destructive action from the Maintenance folder grid.

```swift
// apps/agent/native/sentinel-app/Sentry/MaintenanceHostInjections.swift:51-54 — current
FolderAction(systemImage: "trash", label: String(localized: "Clear NotchDrop Tray"), isDanger: true) {
    Task { @MainActor in
        SentinelController.shared.clearNotchDropTray()
    }
}
```

This action is rare, so a deliberate two-second hold improves safety without slowing normal workflow. A plain confirmation alert is not the target: the pointer-down state should show the user what will happen before it happens.

## Target

Both “清空” entry points must require one uninterrupted **2.0-second press-and-hold** before calling their existing actions.

```swift
// Target interaction contract
// Pointer down: reveal a danger-colored fill overlay from 0% to 100%.
// Hold duration: Animation.linear(duration: 2.0)
// Complete: invoke the existing clearTray / FolderAction.action exactly once.
// Release or cancel before completion: invoke no destructive action.
// Reset: opacity/progress returns to 0 with Animation.easeInOut(duration: 0.2).
```

Only the overlay’s `opacity` and horizontal reveal transform may animate. Do not animate layout, padding, corner radius, width, height, or the surrounding grid.

For `@Environment(\.accessibilityReduceMotion) == true`, preserve the same two-second hold and visible danger fill, but remove any position/scale motion: animate only the overlay opacity from 0 to 1 over `Animation.linear(duration: 2.0)` and reset it with `Animation.easeInOut(duration: 0.2)`.

The two UI entry points must have identical behavior:

- The NotchDrop menu’s “清空” tile.
- The Maintenance page’s `Clear NotchDrop Tray` tile only.

Do not force a hold for every `isDanger` action; danger styling and destructive file deletion are not equivalent concepts.

## Repo conventions to follow

- The UI is SwiftUI and uses local declaration-based motion; do not add a motion library.
- `apps/agent/swift/Sources/CicadaUI/Views/NotchDrop/NotchMenu.swift:79-98` already keeps pointer feedback in a view-local `@State` and uses `.onHover`.
- `docs/Design.md:1000-1002` establishes `Animation.easeInOut(duration: 0.2)` as an existing short UI timing value.
- `apps/agent/swift/Sources/CicadaUI/Views/Alarm/AlarmEye.swift:11,164-176` is the project exemplar for `accessibilityReduceMotion`; it reduces motion without hiding the state.
- The shared CicadaUI module must remain independent of AppKit. Keep actual deletion in the existing host/delegate closures.

## Steps

1. In `apps/agent/swift/Sources/CicadaUI/Models/ReadinessItem.swift`, extend `FolderAction` with an explicit public boolean such as `requiresHoldConfirmation`, defaulting to `false`. Keep `isDanger` unchanged and do not infer confirmation from label text or icon names.
2. In `apps/agent/swift/Sources/CicadaUI/State/HostInjections.swift`, do not change the six preview/default actions: their `action` closures are intentionally empty. They receive the new initializer default (`requiresHoldConfirmation == false`) and must remain usable as before.
3. In `apps/agent/native/sentinel-app/Sentry/MaintenanceHostInjections.swift`, set `requiresHoldConfirmation: true` only on `Clear NotchDrop Tray`; keep open-folder, open-config, and data-directory actions as one-click actions.
4. Add one reusable, internal SwiftUI hold-to-confirm control under `apps/agent/swift/Sources/CicadaUI/Components/`. It must accept an action, an `@ViewBuilder` label, and preserve the caller’s visual hierarchy. It owns the press state and completion guard so fast re-presses cannot invoke the action twice.
5. Implement the control with a `LongPressGesture(minimumDuration: 2.0)` plus a pressing-state callback. On pointer-down, animate progress to full with `Animation.linear(duration: 2.0)`; on early release/cancel, invalidate that in-flight progress and reset with `Animation.easeInOut(duration: 0.2)`; on successful completion, call the action once then reset. Ensure a late completion from a cancelled hold cannot delete files.
6. Render the progress as an overlay clipped to the button’s existing rounded shape. Animate only its opacity and transform-based horizontal reveal. Preserve each caller’s current color, border, icon, size, and hover behavior.
7. In `apps/agent/swift/Sources/CicadaUI/Views/NotchDrop/NotchMenu.swift`, use the control only for the trash tile. The other five menu actions must retain their current one-click `Button` behavior and their `1.05` hover scale.
8. In `apps/agent/swift/Sources/CicadaUI/Components/FolderGridButton.swift`, use the control only when `action.requiresHoldConfirmation` is true. All other folder actions must remain regular buttons. Keep the implementation compatible with the grid’s existing `FolderButton` layout.
9. Add focused tests in `apps/agent/swift/Tests/CicadaUITests/CicadaUITests.swift` for the `FolderAction` default and the extracted hold-state reducer/helper: defaults do not require a hold, a short press never marks completion, cancellation resets progress, and one completed hold emits one action token. If the project cannot reliably drive SwiftUI long-press gestures in SwiftPM, test that non-UI state helper rather than adding a UI-testing framework. Add the host-specific `requiresHoldConfirmation: true` assertion to the existing Sentry/Xcode test target only if that target already covers `MaintenanceHostInjections`; otherwise keep it a manual integration check.

## Boundaries

- Do NOT change `TrayDrop.delete`, `TrayDrop.removeAll`, file-retention behavior, storage paths, or the actual deletion API.
- Do NOT add an alert, a second dialog, haptics, a new dependency, or an animation framework.
- Do NOT require holds for Close, AirDrop, GitHub, Sponsor, Settings, folder-opening, or non-file destructive-looking actions.
- Do NOT animate layout-affecting properties or use `repeatForever`.
- If the current code has drifted from commit `f1f4588`, stop and report the mismatch instead of guessing where the destructive action is wired.

## Verification

- **Mechanical**:
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer pnpm run test:agent`
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer pnpm run build`
  - Expected: both complete successfully; no new dependencies or generated files are required.
- **Feel check**:
  - Add a harmless tray item, press the tray-clear tile for less than two seconds, and confirm the item remains.
  - Hold for exactly two seconds and confirm the fill reaches completion once, the item is deleted once, and the Notch panel follows its existing close behavior.
  - Release at 25%, 50%, and 90%; confirm the fill resets in 200ms and no deletion occurs.
  - Repeat from both the Notch menu and Maintenance grid; their duration and result must match.
  - Enable macOS **Accessibility → Display → Reduce motion**. Confirm the two-second safety feedback remains visible, but no tile or overlay moves or scales.
  - Inspect in slow motion: no width/height/padding/position animation, no double execution after rapid pressing, and no stuck progress after cancellation.
- **Done when**: both file-deleting entry points require a visible two-second hold, cancellation is safe, and every other action retains its existing one-click behavior.
