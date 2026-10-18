# CicadaRelay

Cloudflare Worker + Durable Objects relay for Cicada agent sessions and the iOS
Shortcuts HTTP gateway.

Relay is no longer a plaintext command service and no longer exposes a separate
controller role. The Mac agent keeps a WebSocket connection open. iOS Shortcuts
uses a scoped capability token over HTTPS. Relay can see Shortcuts commands and
results; this path is intentionally not E2EE.

## Runtime

- Worker entry: `src/index.ts`
- Agent WebSocket route: `GET /relay/:liveSession`
- Shortcuts command route: `POST /v1/shortcuts/command`
- Status routes: `GET /status`, `GET /status?device_id=...`, `GET /devices`
- Durable Object binding: `CICADA_SESSIONS`
- Registry DO name: `__cicada_device_registry__`

The same Durable Object class backs session rooms and the global registry.
Session rooms keep one agent socket per live session. The registry stores
`deviceId -> liveSession/status/agentIdentityPublicKey/shortcutGrants`.

## Environment

Optional:

| Name | Default | Purpose |
|---|---|---|
| `RATE_LIMIT_ENABLED` | enabled | Best-effort limit of 100 requests per minute per client IP, counted independently by each Worker instance (isolate), not globally. Set to `false` only for local tests. |
| `ENABLE_CORS` | `false` | Enables configured CORS headers. |
| `ALLOWED_ORIGINS` | local dev origins | Comma-separated allow list when CORS is enabled. |
| `DEBUG_MODE` | `false` | Enables debug-level structured logs. |

For local development, copy `.dev.vars.example` to the ignored `.dev.vars` file. The
`CICADA_SESSIONS` Durable Object binding comes from `wrangler.toml` and must not be copied into the
variables file.

Do not commit `.env`, `.dev.vars`, secrets, Wrangler state, coverage output,
build output, or local `.cicada` state.

### Administrator secret

`CICADA_ADMIN_TOKEN` is an optional **secret**, not an ordinary variable. It is used
only by `POST /v1/admin/device-reset` to clear a device's trust-on-first-use (TOFU)
identity binding. This is the only recovery path for registration after the
agent's identity key is lost or rotated. Without the secret, the endpoint is
unavailable and returns 404.

From the monorepo root, set it interactively (enter the value at Wrangler's prompt):

```bash
bun run --cwd apps/relay wrangler secret put CICADA_ADMIN_TOKEN
```

Do not put the value in `wrangler.toml` or `.dev.vars.example`. To rotate it, run
the same `secret put` command and enter a new value; update the administrator's
Bearer credential to match. To remove it and disable the endpoint:

```bash
bun run --cwd apps/relay wrangler secret delete CICADA_ADMIN_TOKEN
```

Only reset a verified legitimate device when its agent is about to reconnect:
after reset, the next agent connecting with that `device_id` will bind its public
key. An unintended agent could claim the identity first.

Example with placeholder credentials and device ID (replace both before use):

```bash
curl -X POST 'https://relay.example.com/v1/admin/device-reset' \
  -H 'Authorization: Bearer <ADMIN_TOKEN>' \
  -H 'Content-Type: application/json' \
  --data '{"device_id":"MAC_0123456789ABCDEF0123456789ABCDEF"}'
```

Successful response:

```json
{"ok":true,"deviceId":"MAC_0123456789ABCDEF0123456789ABCDEF","existed":true}
```

`existed` is false if no registry entry existed. A missing or incorrect Bearer
token returns 401 when the secret is configured; malformed JSON or an invalid
`device_id` returns 400. Device IDs must be `MAC_` followed by 32 hexadecimal
characters. See the [deployment runbook](../../docs/runbooks/relay-deploy.md#administrator-device-recovery)
for the recovery procedure.

Production logging, alert definitions, and request-ID diagnosis are documented in
[`docs/runbooks/relay-observability.md`](../../docs/runbooks/relay-observability.md).

## Agent WebSocket

```bash
wscat -c "wss://relay.example.com/relay/live-random-session" \
  -H "x-device-id: MAC_1234567890ABCDEF1234567890ABCDEF" \
  -H "x-agent-identity-public-key: <ed25519-public-key-base64>"
```

Visible control messages:

```json
{"type":"shortcut_grant_update","from":"agent","data":{"state":"active","grant":{"grantId":"grant-1","deviceId":"MAC_...","name":"iPhone","tokenHash":"base64url","tokenPreview":"cicada_sc_ab...1234","allowedCommands":["ping","status"],"expiresAt":1706659200000,"createdAt":1704067200000,"updatedAt":1704067200000}}}
{"type":"shortcut_grant_update_ack","ok":true,"grantId":"grant-1","state":"active","sent_at":1704067200001}
{"type":"shortcut_command","id":"req-1","data":{"requestId":"req-1","grantId":"grant-1","command":"ping"}}
{"type":"shortcut_result","id":"req-1","from":"agent","data":{"requestId":"req-1","command":"ping","ok":true,"success":true,"message":"pong"}}
{"type":"ping","id":"ping-1","sent_at":1704067200000}
{"type":"pong","id":"ping-1","sent_at":1704067200001}
```

Relay close codes:

| Code | Meaning |
|---|---|
| `4000` | Invalid session or removed role |
| `4001` | Previous agent connection replaced |
| `4002` | Agent unavailable |
| `4004` | Reserved temporary agent absence |

## Shortcuts Setup

1. Set up and start the Mac agent:

```bash
cicada setup --relay-url https://relay.example.com
cicada start
cicada status
```

Confirm `/devices` shows it online.

2. On the Mac, create a Shortcuts grant:

```bash
cicada shortcut create --name iPhone --commands ping,status --ttl 30d
```

The full `cicada_sc_...` token is printed once. Store it in the iOS Shortcut.
Daemon state and logs only expose the token preview.

3. In iOS Shortcuts, use **Get Contents of URL**:

```text
URL: https://relay.example.com/v1/shortcuts/command
Method: POST
Headers:
  Authorization: Bearer cicada_sc_<token>
  Content-Type: application/json
Body:
  {"device_id":"MAC_...","command":"ping","request_id":"shortcut-ping"}
```

4. Read `ok`, `success`, `message`, and optional `data` from the JSON response.

Grant management:

```bash
cicada shortcut list
cicada shortcut revoke <grantId>
```

Default grant scope is `ping,status`. `--commands all` grants every command in the
[command table](../../packages/shared/COMMANDS.md#current-commands), including
`shutdown` (shut down), `restart` (restart), `sleep` (sleep, interrupting remote control),
`daemon_exit` (exit the remote control service), `app_close` (close an app, potentially
losing unsaved work), `screenshot` (capture the screen and return the image through Relay),
`sentry_stop` (stop Sentinel), and `sentry_unlock` (clear the Sentinel alarm).
Use it only when the Shortcut needs all of these permissions.

## Local Validation

From the monorepo root:

```bash
bun run build:relay
bun run lint:relay
bun run test:relay
bun run --cwd apps/relay test:coverage
bun run deploy:relay:dry-run
```
