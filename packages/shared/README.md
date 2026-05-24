# @cicada/shared

Shared TypeScript contracts for Cicada Relay transport, Shortcuts gateway, command names, validation, errors, and utilities.

## Scope

`@cicada/shared` is the TypeScript source of truth for:

1. Relay agent transport and Shortcuts envelopes: `src/types/relay-transport.types.ts`
2. Command names and command request types: `src/types/command.types.ts`
3. Command validation: `src/validators/command.validator.ts`
4. Shared API envelopes and errors.

Swift mirrors the command and Shortcuts grant contract in `apps/agent/swift/Sources/CicadaCore` and `apps/agent/swift/Sources/CicadaRelayClient`.

## Development

```bash
cd /path/to/Cicada/packages/shared
pnpm run build
pnpm run dev
pnpm run clean
```

## Change Flow

1. Update the relevant type or validator under `src/`.
2. Update `COMMANDS.md`.
3. Update Swift mirrors when command or Shortcuts payload shape changes.
4. Run Relay and Agent validation from the monorepo root.

```bash
pnpm run build:relay
pnpm run lint:relay
pnpm run test:relay
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer pnpm run lint:agent
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer pnpm run test:agent
```

## Related Docs

1. [Command And Transport Contract](./COMMANDS.md)
2. [Relay README](../../apps/relay/README.md)
3. [Command Validation Architecture](../../docs/architecture/command-validation.md)
4. [Validation Best Practices](../../docs/best-practices/validation.md)
5. [Relay Deploy Runbook](../../docs/runbooks/relay-deploy.md)
