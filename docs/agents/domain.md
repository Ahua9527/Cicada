# Domain Docs

How engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- `CONTEXT-MAP.md` at the repo root, if it exists. It points to the context document relevant to the work.
- The applicable context document:
  - `apps/relay/CONTEXT.md`
  - `apps/agent/CONTEXT.md`
  - `packages/shared/CONTEXT.md`
- `docs/adr/` for system-wide decisions.
- The applicable context-specific ADR directory:
  - `apps/relay/docs/adr/`
  - `apps/agent/docs/adr/`
  - `packages/shared/docs/adr/`

If any of these files do not exist, proceed silently. The domain-modeling workflow creates them when terms or decisions are actually resolved.

## File structure

```text
/
├── CONTEXT-MAP.md
├── docs/adr/                         ← system-wide decisions
├── apps/
│   ├── relay/
│   │   ├── CONTEXT.md
│   │   └── docs/adr/
│   └── agent/
│       ├── CONTEXT.md
│       └── docs/adr/
└── packages/shared/
    ├── CONTEXT.md
    └── docs/adr/
```

## Use the glossary's vocabulary

When naming a domain concept in an issue, proposal, hypothesis, or test, use the terminology defined by the relevant `CONTEXT.md`. If it is absent, reconsider whether the codebase already uses another term, or note a real gap for domain modeling.

## Flag ADR conflicts

If output contradicts an existing ADR, surface that explicitly rather than silently overriding it.
