# Validation Best Practices

## Authentication

- Shortcuts requests authenticate only with `Authorization: Bearer cicada_sc_<token>`.
- Agent identity is Ed25519 and first-seen bound by `deviceId`.
- Re-registering an already-bound agent identity requires signature, timestamp, and nonce.
- Shortcuts use `Authorization: Bearer cicada_sc_<token>`.
- Relay and agent store only shortcut token hashes and previews.
- Keep real secrets in Wrangler or local shell-managed config, never in repo files.

## Logging

Never log:

- API keys or future admin tokens
- Authorization headers
- full `cicada_sc_...` tokens
- shortcut token hashes
- nonces or signatures
- shortcut command payloads when they include user parameters
- full `/relay/:session_or_token` path segments

Operational logs should use request id, route shape, status, grant preview, and
redacted device/session summaries.

## Commands

- Keep the command set at the current 9 commands unless a separate protocol change is approved.
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

## Rate Limits And CORS

- Rate limiting is enabled unless `RATE_LIMIT_ENABLED=false`.
- Keep `RATE_LIMIT_ENABLED=false` limited to local/integration fixtures.
- CORS is disabled unless `ENABLE_CORS=true`.
- When CORS is enabled, set `ALLOWED_ORIGINS` explicitly for deployed environments.
