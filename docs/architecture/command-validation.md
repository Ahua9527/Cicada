# Command And Shortcuts Architecture

## Boundary

Cicada Relay has one user-facing control path: iOS Shortcuts HTTP API. There is
no public controller role, no trusted-controller reconnect, and no controller
WebSocket.

Relay owns:

- online agent session rooms
- global device registry
- first-seen agent identity binding
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
- Command list: `packages/shared/src/types/command.types.ts`
- Swift command list: `apps/agent/swift/Sources/CicadaCore/Models.swift`
- Swift grant model: `apps/agent/swift/Sources/CicadaCore/ShortcutGrant.swift`

## Flow

1. Agent opens `GET /relay/:liveSession` with `x-device-id` and `x-agent-identity-public-key`.
2. Registry first-seen binds `deviceId -> agentIdentityPublicKey`.
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
