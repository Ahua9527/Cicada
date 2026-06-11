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
- Bark vendor route: `/bark/*` by default, or Worker root when `BARK_ROOT_PATH=/`
- Status routes: `GET /status`, `GET /status?device_id=...`, `GET /devices`
- Durable Object binding: `CICADA_SESSIONS`
- Bark D1 binding: `BARK_DATABASE`
- Registry DO name: `__cicada_device_registry__`

The same Durable Object class backs session rooms and the global registry.
Session rooms keep one agent socket per live session. The registry stores
`deviceId -> liveSession/status/agentIdentityPublicKey/shortcutGrants`.

## Environment

Optional:

| Name | Default | Purpose |
|---|---|---|
| `RATE_LIMIT_ENABLED` | enabled | Set to `false` only for local tests. |
| `ENABLE_CORS` | `false` | Enables configured CORS headers. |
| `ALLOWED_ORIGINS` | local dev origins | Comma-separated allow list when CORS is enabled. |
| `DEBUG_MODE` | `false` | Enables debug-level structured logs. |
| `BARK_ROOT_PATH` | `/bark` | Mount path for the vendored Bark Worker. Set to `/` to expose Bark at Worker root while keeping existing Cicada routes. |
| `BARK_BASIC_AUTH` | unset | Optional Basic Auth credential in `user:pass` form for Bark protected endpoints. |
| `BARK_ALLOW_NEW_DEVICE` | `true` | Forwarded to Bark registration behavior. Set `false` to block new devices. |
| `BARK_ALLOW_QUERY_NUMS` | `true` | Forwarded to Bark `/info` device counting behavior. |

Bark APNs values must be injected through deployed Worker secrets or local
`apps/relay/.env`, not committed to this repository. Wrangler loads local
`.env` values from the same directory as `wrangler.toml`.

| Secret | Purpose |
|---|---|
| `BARK_APNS_PRIVATE_KEY` | APNs `.p8` private key PEM. |
| `BARK_APNS_TEAM_ID` | Apple Developer Team ID. |
| `BARK_APNS_KEY_ID` | APNs Auth Key ID. |
| `BARK_APNS_TOPIC` | APNs topic, for example the Bark app bundle ID. |
| `BARK_APNS_HOST_NAME` | Optional APNs host override. Defaults to `api.push.apple.com`. |

For deployed Workers, set sensitive APNs values as secrets:

```bash
wrangler secret put BARK_APNS_PRIVATE_KEY
wrangler secret put BARK_APNS_TEAM_ID
wrangler secret put BARK_APNS_KEY_ID
wrangler secret put BARK_APNS_TOPIC
```

For local development, copy `apps/relay/.env.example` to `apps/relay/.env` and
replace the `TODO_...` placeholders with authorized APNs values. Do not create
both `.dev.vars` and `.env` for the same local run; when `.dev.vars` exists,
Wrangler does not include `.env` values in the Worker `env` object.

`BARK_DATABASE` is a D1 binding configured in `wrangler.toml`, not a dotenv
string. Create and bind the D1 database before exercising Bark registration or
push flows.

Do not commit `.env`, `.dev.vars`, secrets, Wrangler state, coverage output,
build output, or local `.cicada` state.

## Bark Vendor

Relay vendors `cwxiaos/bark-worker` at commit
`8bfd70c369b6dba3dbe53aad96d79a4367f57a45` under
`vendor/bark-worker`. The upstream GPLv3 license and source notices are
preserved there. This introduces GPLv3 compliance obligations for Relay
distributions that include the vendor code.

The adapter in `src/presentation/routes/bark.route.ts` only mounts Bark and maps
Cicada env names to Bark's original env shape. Bark still provides
`register`, `ping`, `healthz`, `info`, push path parsing, batch `device_keys`,
Basic Auth, MCP sessions, and APNs auth-token caching through the vendored
handler.

Create and bind the Bark D1 database before deploying Bark:

```bash
wrangler d1 create cicada-bark
wrangler d1 migrations apply cicada-bark \
  --migrations-dir vendor/bark-worker/migrations
```

Then replace the placeholder `database_id` in the existing `[[d1_databases]]`
block in `wrangler.toml` with the created database ID. Keep
`migrations_dir = "vendor/bark-worker/migrations"` so Wrangler reads the
vendored Bark migration files from their isolated directory.

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

Default grant scope is `ping,status`. Use `--commands all` only when the
Shortcut should be allowed to run all current 14 commands.

## Local Validation

From the monorepo root:

```bash
pnpm run build:relay
pnpm run lint:relay
pnpm run test:relay
pnpm --filter @cicada/relay exec jest --coverage --silent
pnpm run deploy:relay:dry-run
```
