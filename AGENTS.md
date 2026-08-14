# Repository Guidelines

## Project Structure & Module Organization

Cicada is a monorepo for a Cloudflare Relay, a macOS Swift agent, and shared
protocol contracts. `apps/relay` contains the TypeScript Worker, Durable Object,
middleware, routes, controllers, and Jest tests. `apps/agent` contains the Swift
CLI, LaunchAgent daemon, notifier, assets, and shell scripts. `packages/shared`
is the single source of truth for TypeScript command types, validators, errors,
and shared utilities. Keep protocol changes centralized there, then check the
Swift model and command gateway for compatibility.

## Build, Test, and Development Commands

Install dependencies from the repository root:

```bash
pnpm install
```

Use root scripts for normal validation:

```bash
pnpm run build              # build shared + relay, then Swift agent binaries
pnpm run lint               # ESLint relay + Swift compile lint
pnpm run test               # Jest relay tests + SwiftPM tests
pnpm run deploy:relay:dry-run
```

For macOS agent checks, prefer the same Xcode path used by CI:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer pnpm run test:agent
```

## Coding Style & Naming Conventions

TypeScript uses ES modules, strict `tsconfig` settings, ESLint, and Prettier.
Follow the relay `.editorconfig`: UTF-8, LF endings, final newline, 2-space
indentation for JS/TS/JSON/YAML/TOML. Prettier uses semicolons, single quotes,
trailing commas, and 100-column TypeScript formatting. Name tests
`*.test.ts` or `*.spec.ts`. Swift code is SwiftPM-based, targets macOS 13, and
uses module names such as `CicadaCore`, `CicadaSystem`, and `CicadaRelayClient`.

## Testing Guidelines

Relay tests live under `apps/relay/test` with `unit`, `integration`,
`security`, and `performance` areas. Run `pnpm run test:relay`; use
`pnpm --filter @cicada/relay run test:coverage` when checking coverage. Jest
coverage thresholds are 70% for branches, functions, lines, and statements.
Swift tests live under `apps/agent/swift/Tests` and run through
`pnpm run test:agent`.

## Commit & Pull Request Guidelines

Use Conventional Commits matching current history, for example
`ci: add monorepo validation workflows`, `refactor(agent): move Swift agent`,
or `refactor(shared): promote shared package`. Keep commits scoped and
reviewable. Pull requests should describe the touched area, list validation
commands, link related issues when available, and include screenshots or logs
for user-visible, daemon, deployment, or configuration changes.

## Security & Configuration Tips

Do not commit secrets, `.env`, `.dev.vars`, `.mcp.json`, Wrangler state, build
outputs, coverage, or local `.cicada` runtime files. Use example values in docs
and keep real API keys in the local environment or deployment platform.

## Agent skills

### Issue tracker

Issues and specifications are tracked in GitHub Issues for this repository. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default five canonical triage labels. See `docs/agents/triage-labels.md`.

### Domain docs

This is a multi-context repository: `apps/relay`, `apps/agent`, and `packages/shared` each have their own domain context. See `docs/agents/domain.md`.
