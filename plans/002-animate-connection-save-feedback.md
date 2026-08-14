# 002 — Animate Relay connection save feedback

- **Status**: IMPLEMENTED — manual feel check pending
- **Commit**: f1f4588
- **Severity**: MEDIUM
- **Category**: Missed opportunity; feedback; accessibility
- **Estimated scope**: 2–3 Swift files and focused model/UI tests

## Problem

The Relay connection save operation moves through `.saving` and then `.ok` or `.err`, but the confirmation view appears abruptly whenever the conditional becomes true.

```swift
// apps/agent/swift/Sources/CicadaUI/State/ConfigModel.swift:57-67 — current
public func saveConnection() async {
    connectionSaveState = .saving
    do {
        var latest = (try? store.load()) ?? draft
        latest.relayURL = draft.relayURL
        try store.save(latest)
        draft = latest
        connectionSaveState = .ok
    } catch {
        connectionSaveState = .err(error.localizedDescription)
    }
}

// apps/agent/swift/Sources/CicadaUI/Views/SettingsCards/ConnectionCard.swift:15-22 — current
HStack {
    Button(String(localized: "保存", bundle: .module)) {
        Task { await model.saveConnection() }
    }
    .buttonStyle(PrimaryButtonStyle())
    if let msg = inlineMessage {
        InlineMessage(kind: msg.kind, text: msg.text)
    }
}
```

The project design specifies this exact missing transition in `docs/Design.md:1000`: an inline message should enter via opacity plus a top-edge move.

## Target

When the save state changes between “no message” and either success or error, the message must transition in and out using only opacity and a transform-based vertical move.

```swift
// Target values
withAnimation(.easeInOut(duration: 0.2)) {
    // change the presentation state that inserts/removes InlineMessage
}

InlineMessage(kind: msg.kind, text: msg.text)
    .transition(.opacity.combined(with: .move(edge: .top)))
```

On Reduce Motion, preserve the feedback but drop the movement:

```swift
InlineMessage(kind: msg.kind, text: msg.text)
    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
```

The reduced-motion branch must retain the same `Animation.easeInOut(duration: 0.2)` timing. The message must not animate width, height, spacing, padding, or its parent card layout.

## Repo conventions to follow

- `apps/agent/swift/Sources/CicadaUI/Views/SettingsPane.swift:20-28,72-74` already uses conditional content, `.transition(.opacity)`, and short explicit SwiftUI animation.
- `docs/Design.md:1000-1001` is the project’s explicit specification for inline feedback and the existing `0.2s` settings-tab timing.
- `apps/agent/swift/Sources/CicadaUI/Views/Alarm/AlarmEye.swift:11,164-176` demonstrates the project’s reduced-motion environment pattern.
- Keep ownership of persistence state in `ConfigModel`; `ConnectionCard` should only choose how that state is presented.

## Steps

1. In `apps/agent/swift/Sources/CicadaUI/Views/SettingsCards/ConnectionCard.swift`, read `@Environment(\.accessibilityReduceMotion)` and derive a named `AnyTransition` (or equivalent computed transition) that is `.opacity` under Reduce Motion and `.opacity.combined(with: .move(edge: .top))` otherwise.
2. Attach that transition to the existing `InlineMessage` conditional. Do not add a second status view or replace the current success/error copy.
3. Ensure the `.saving → .ok/.err` presentation update is wrapped in `withAnimation(.easeInOut(duration: 0.2))` at the view boundary. Do not move file I/O, error mapping, or `connectionSaveState` ownership out of `ConfigModel` solely for animation.
4. Check the repeat-save case: pressing Save after a previous success must not leave an old message layered under a new one. The current `.saving` state should remove the message, and the next terminal result should use the same transition.
5. Add/extend tests around `ConfigModel.saveConnection()` as needed to preserve `.saving → .ok/.err` semantics. If a SwiftUI transition cannot be asserted in SwiftPM, add a targeted source-level/UI-host test only if the existing test setup supports it; otherwise document it as a manual feel check rather than adding a UI-testing framework.

## Boundaries

- Do NOT animate the Save button, text field, card, tab bar, or page navigation as part of this change.
- Do NOT add a loading spinner, auto-dismiss timer, toast system, or new dependency.
- Do NOT change how Relay URLs are saved, validated, merged, or reported.
- Do NOT use `scale(0)`, a layout animation, or a continuous animation.
- If the current code differs from commit `f1f4588`, stop and re-establish the state-to-view mapping before editing.

## Verification

- **Mechanical**:
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer pnpm run test:agent`
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer pnpm run build`
  - Expected: existing save-state tests pass and the app builds without new dependencies.
- **Feel check**:
  - Save a valid Relay URL. The success message should arrive within a responsive 200ms transition from just above its settled position; the surrounding row must not reflow visibly.
  - Cause a safe save error in a test/local configuration. Confirm the error uses the identical motion and is immediately readable.
  - Press Save repeatedly after an existing success. Confirm there is never a duplicated or overlapping message.
  - Enable macOS **Accessibility → Display → Reduce motion**. Confirm messages still fade in/out over 200ms but do not move vertically.
  - Slow the animation in Xcode Instruments/Core Animation tools if available and confirm only opacity and transform change.
- **Done when**: both terminal save outcomes have a short, interruptible transition; Reduce Motion retains opacity feedback; persistence behavior is unchanged.
