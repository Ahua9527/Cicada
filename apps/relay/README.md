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
- Status routes: `GET /status` and `GET /health` (public); `GET /status?device_id=...` and
  `GET /devices` (administrator token)
- Admin routes: `POST /v1/admin/enrollment-codes`, `POST /v1/admin/device-reset`
  (administrator token)
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

`CICADA_ADMIN_TOKEN` is an optional **secret**, not an ordinary variable. Requests send it as
`Authorization: Bearer <token>`. It is required by:

- `POST /v1/admin/enrollment-codes`: issue a one-time enrollment code. A device ID that has no
  bound identity key can only register for the first time with such a code.
- `POST /v1/admin/device-reset`: clear a device's identity binding, so a replaced or reinstalled
  Mac can enroll again with a new code.
- `GET /devices` and `GET /status?device_id=...`: read device state.

Without the secret these endpoints return 404 as if they did not exist, so no new device can
enroll. `GET /status` without `device_id` and `GET /health` stay public.

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

#### Enrollment codes

Issue a code right before setting up a Mac that has never registered (placeholder token; replace
it before use):

```bash
curl -X POST 'https://relay.example.com/v1/admin/enrollment-codes' \
  -H 'Authorization: Bearer <ADMIN_TOKEN>'
```

```json
{"ok":true,"enrollmentCode":"cicada_enroll_<random>","expiresAt":1704067800000}
```

The code appears only in this response, which is sent with `Cache-Control: no-store`; Relay stores
only its SHA-256 hash and never logs it. It is valid for 10 minutes (`expiresAt` is Unix
milliseconds), works once, and is not tied to a device ID in advance. The Mac sends it in the
`x-agent-enrollment-code` header and signs it in the v2 registration transcript (see
[Agent Registration](../../packages/shared/COMMANDS.md#agent-registration)). After the first
successful registration the code is void and the device ID stays bound to that identity key; later
connections need no code. Devices bound before enrollment codes existed are not affected.

The Mac agent does not send enrollment codes yet; that support ships separately. Until then, only
devices that are already bound can connect, and a device that is reset cannot register again.

A rejected first registration fails the WebSocket upgrade with 429 and a `code` such as
`agent_enrollment_code_required`, `agent_enrollment_code_invalid`, `agent_enrollment_code_expired`,
`agent_enrollment_code_used`, or `invalid_agent_registration_signature`. Guessing codes is not
practical: each code has 128 random bits, every attempt is a WebSocket upgrade under the per-IP
rate limit, and invalid, expired, or used codes are logged as
`security_event=agent_enrollment_rejected` (without the code).

#### Device reset

After a reset the device ID is unbound: its old key no longer connects, and the Mac must enroll
again with a new enrollment code. Without a valid code no other agent can claim the device ID.

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
  -H "x-agent-identity-public-key: <ed25519-public-key-base64>" \
  -H "x-agent-registration-timestamp: <unix-ms>" \
  -H "x-agent-registration-nonce: <random>" \
  -H "x-agent-registration-signature: <ed25519-signature-base64>"
```

A device ID that is not bound yet also sends `x-agent-enrollment-code` and signs the v2
transcript; see [Agent Registration](../../packages/shared/COMMANDS.md#agent-registration).

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

A Mac whose device ID is not bound yet needs a one-time enrollment code for its first connection
(see [Enrollment codes](#enrollment-codes)). Confirm the Mac is online (administrator token
required):

```bash
curl 'https://relay.example.com/devices' -H 'Authorization: Bearer <ADMIN_TOKEN>'
```

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
[command table](../../packages/shared/COMMANDS.md#current-commands) except the ones marked
high risk: `shutdown` (shut down), `restart` (restart), `sleep` (sleep, interrupting remote
control), `daemon_exit` (exit the remote control service), `app_close` (close an app,
potentially losing unsaved work), `screenshot` (capture the screen and return the image
through Relay), `sentry_stop` (stop Sentinel), and `sentry_unlock` (clear the Sentinel alarm).
Name a high-risk command explicitly to grant it, for example `--commands all,shutdown`.
Grants created before this change keep their existing command list.

## Local Validation

From the monorepo root:

```bash
bun run build:relay
bun run lint:relay
bun run test:relay
bun run --cwd apps/relay test:coverage
bun run deploy:relay:dry-run
```
