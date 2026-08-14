# 003 — Add restrained hover feedback to maintenance actions

- **Status**: IMPLEMENTED — manual feel check pending
- **Commit**: f1f4588
- **Severity**: LOW
- **Category**: Missed opportunity; feedback; cohesion
- **Estimated scope**: 1 Swift file and visual verification

## Problem

The Maintenance folder-grid tile already changes its background and border when hovered, but it changes with no motion. The project design explicitly prescribes a restrained hover scale for this exact component.

```swift
// apps/agent/swift/Sources/CicadaUI/Components/FolderGridButton.swift:37-50 — current
.frame(maxWidth: .infinity)
.padding(DesignMetrics.Spacing.s4)
.background(hover ? Color.cicadaAccent.opacity(0.12) : Color.cicadaBgBase)
.overlay(
    RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
        .stroke(
            hover ? AnyShapeStyle(.cicadaAccent.opacity(0.3)) : AnyShapeStyle(.cicadaBorderSubtle),
            lineWidth: 1
        )
)
.clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
...
.buttonStyle(.plain)
.onHover { hover = $0 }
```

`docs/Design.md:997` specifies the exact intended interaction: `scaleEffect(hover ? 1.02 : 1)` with `.spring(response: 0.2)`.

## Target

Hovering a maintenance action should provide a subtle transform-only acknowledgement. It must not delay click handling or make the dense operations grid feel playful.

```swift
// Target values
.scaleEffect(hover ? 1.02 : 1)
.animation(.spring(response: 0.2), value: hover)
.onHover { hover = $0 }
```

Apply the animation only to the scale effect. The existing background and border color changes may remain instantaneous, so no layout or broad implicit animation is introduced. `onHover` is macOS pointer-specific; no web-style hover media query applies in this native SwiftUI view.

For Reduce Motion, retain this immediate hover feedback as specified in `docs/Design.md:1038`; it is not continuous motion. Do not add another reduce-motion branch for this one interaction.

## Repo conventions to follow

- `apps/agent/swift/Sources/CicadaUI/Views/NotchDrop/NotchMenu.swift:79-98` is the closest live exemplar: hover state in `@State`, `scaleEffect`, then `.animation(.spring(response: 0.2), value: hover)`.
- `docs/Design.md:997` is the exact intended value for `FolderButton`.
- Use SwiftUI’s standard `.spring(response: 0.2)` exactly; do not add custom durations, bounce values, tokens, or a dependency.

## Steps

1. In `apps/agent/swift/Sources/CicadaUI/Components/FolderGridButton.swift`, add `.scaleEffect(hover ? 1.02 : 1)` to `FolderButton`’s label after its visual shape is established.
2. Attach `.animation(.spring(response: 0.2), value: hover)` narrowly enough that the transform responds to hover, but do not convert the card’s color/border changes into a broad layout animation.
3. Keep the existing `Button`, `.buttonStyle(.plain)`, click action, icon, labels, and `onHover` handler intact.
4. If plan 001 has already introduced a hold-to-confirm wrapper for the tray-clear tile, preserve that behavior: the hover scale must apply equally to normal and confirmation-required tiles, and must never reset or complete a hold.

## Boundaries

- Do NOT add scale to sidebar navigation, menu-bar commands, settings tabs, text fields, Toggles, or the primary Save button.
- Do NOT change the tile’s `1.02` target scale, `0.2` spring response, colors, spacing, grid columns, click behavior, or destructive-action semantics.
- Do NOT add mouse tracking outside the existing SwiftUI `onHover` mechanism.
- If the current component no longer has the cited `hover` state at commit `f1f4588`, stop and report the drift before choosing a replacement pattern.

## Verification

- **Mechanical**:
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer pnpm run test:agent`
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer pnpm run build`
  - Expected: both pass without new dependencies or unrelated formatting changes.
- **Feel check**:
  - Move the pointer quickly across all six tiles. Each should grow only to `1.02`, retarget smoothly, and never overlap neighbours enough to obscure labels.
  - Click immediately on hover and confirm the original action fires with no delay.
  - Compare against the Notch menu tile hover: this grid feedback should feel quieter because `1.02 < 1.05`.
  - Enable macOS **Accessibility → Display → Reduce motion** and verify the quick hover acknowledgement remains available, with no continuous or positional animation.
  - Inspect slow motion: no frame causes changes to width, height, padding, grid layout, or border geometry.
- **Done when**: every maintenance tile has the specified restrained pointer feedback and all existing actions still behave identically.
