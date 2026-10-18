# Command And Shortcuts Architecture

## Boundary

Cicada Relay has one user-facing control path: iOS Shortcuts HTTP API. There is
no public controller role, no trusted-controller reconnect, and no controller
WebSocket.

Relay owns:

- online agent session rooms
- global device registry
- agent identity binding at first registration, gated by a one-time enrollment code
- shortcut grant registry and capability-token validation
- command scope, TTL, revocation, online-state, and timeout checks
- Shortcuts HTTP request/response bridging to the live agent WebSocket

Swift agent owns:

- agent identity persistence
- shortcut grant creation, hashing, preview, scope, expiry, and revocation
- final grant/scope check before command execution
- command execution and result generation

## Source Of Truth

- TypeScript transport contract: `packages/shared/src/types/relay-transport.types.ts`
- Command list: `packages/shared/src/protocol/commands.ts`
- Swift command list: `apps/agent/swift/Sources/CicadaCore/Models.swift`
- Swift grant model: `apps/agent/swift/Sources/CicadaCore/ShortcutGrant.swift`

## Flow

1. Agent opens `GET /relay/:liveSession` with `x-device-id`, `x-agent-identity-public-key`, and a signed registration ([Agent Registration](../../packages/shared/COMMANDS.md#agent-registration)).
2. On the first registration of a `deviceId` the agent also sends a one-time enrollment code issued by the administrator; the registry consumes it and binds `deviceId -> agentIdentityPublicKey`. Later registrations are verified against the bound key.
3. User creates a Shortcuts token on the Mac with `cicada shortcut create`.
4. Agent stores only token hash/preview/scope/expiry locally and publishes `shortcut_grant_update` to Relay.
5. iOS Shortcut calls `POST /v1/shortcuts/command` with `Authorization: Bearer cicada_sc_<token>`.
6. Registry hashes the bearer token, validates grant active/scope/device/online state, and dispatches `shortcut_command` to the live agent room.
7. Agent validates the grant locally, executes the command, and returns `shortcut_result`.
8. Relay returns the result JSON to Shortcuts. Commands are not queued while the agent is offline.

## Security Boundary

Shortcuts HTTP is not E2EE. Relay can see command names and result messages.
This is intentional for a no-iOS-app workflow. Full tokens must never be logged
or stored by Relay. Agent and Relay store only token hashes and previews.
