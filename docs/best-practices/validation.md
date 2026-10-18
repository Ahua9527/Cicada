# Validation Best Practices

## Authentication

- Shortcuts requests authenticate only with `Authorization: Bearer cicada_sc_<token>`.
- Agent identity is Ed25519 and bound to `deviceId` at its first registration. That registration
  needs a one-time enrollment code from `POST /v1/admin/enrollment-codes`, signed in the v2
  transcript ([Agent Registration](../../packages/shared/COMMANDS.md#agent-registration)).
- Enrollment codes are valid for 10 minutes, work once, and are stored only as SHA-256 hashes.
- Re-registering an already-bound agent identity requires signature, timestamp, and nonce.
- Shortcuts use `Authorization: Bearer cicada_sc_<token>`.
- Relay and agent store only shortcut token hashes and previews.
- Keep real secrets in Wrangler or local shell-managed config, never in repo files.

## Logging

Never log:

- API keys and the `CICADA_ADMIN_TOKEN` administrator secret
- Authorization headers
- full `cicada_sc_...` tokens
- `cicada_enroll_...` enrollment codes
- shortcut token hashes
- nonces or signatures
- shortcut command payloads when they include user parameters
- full `/relay/:session_or_token` path segments

Operational logs should use request id, route shape, status, grant preview, and
redacted device/session summaries.

## Commands

- Adding or removing commands requires a protocol change: update `packages/shared/src/protocol/commands.ts` and `COMMAND_DESCRIPTIONS` in `packages/shared/src/constants/commands.ts`, synchronize Swift's `RemoteCommand`, then run `bun run protocol:generate` to regenerate the contract JSON and [command table](../../packages/shared/COMMANDS.md#current-commands).
- Relay validates Shortcuts command scope from grants.
- Swift agent performs a final grant/scope check before execution.
- Agent ignores `pong`, grant ACK, and other control messages for command logs.

## WebSocket

- Primary agent path is `GET /relay/:liveSession`.
- Agent `ping` receives Relay `pong` on the same socket.
- Duplicate agent connections replace the older socket.

## HTTP

- `POST /v1/shortcuts/command` is the only user-facing control endpoint.
- `GET /devices`, `GET /status`, and `GET /health` are the read-only operational endpoints.
- `GET /devices` and `GET /status?device_id=...` require `Authorization: Bearer <CICADA_ADMIN_TOKEN>`,
  like the admin endpoints `POST /v1/admin/enrollment-codes` and `POST /v1/admin/device-reset`. They
  return 404 when the secret is not configured and 401 for a missing or wrong token. `GET /status`
  without `device_id` and `GET /health` are public.

## Rate Limits And CORS

- Rate limiting is enabled unless `RATE_LIMIT_ENABLED=false`: best-effort, 100 requests per minute per client IP, counted independently by each Worker instance (isolate), not globally.
- Keep `RATE_LIMIT_ENABLED=false` limited to local/integration fixtures.
- CORS is disabled unless `ENABLE_CORS=true`.
- When CORS is enabled, set `ALLOWED_ORIGINS` explicitly for deployed environments.
