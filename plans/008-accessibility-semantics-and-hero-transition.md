# 008 — Add accessible status semantics and Hero handoff

- **Status**: IMPLEMENTED — verification pending
- **Commit**: f1f4588
- **Severity**: MEDIUM
- **Category**: Accessibility; state continuity

## Applied change

`AlarmOverlayContent` hides the decorative `AlarmEye`; `AlarmLeftPanel` hides its decorative icon and combines the alarm title/reason into one accessible summary while leaving Stop as a separate button.

`StatusHeroCard` exposes one combined state summary and crossfades content by stable system-image identity with `easeOut(duration: 0.20)`. `ProgressRing` now exposes a “就绪度” label and percent value.

## Boundaries

- Do not alter AlarmEye’s documented 20-second rotation or 2-second pulse.
- Do not animate Hero layout, scale, or position.

## Verification

- VoiceOver should announce meaningful alarm, Hero, and readiness information once without decorative duplicates.
- State changes should never replay on an unchanged polling value.
