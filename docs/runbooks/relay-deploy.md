# Relay Deploy Runbook

## Preflight

From the monorepo root:

```bash
bun run build:relay
bun run lint:relay
bun run test:relay
bun run --cwd apps/relay test:coverage
bun run deploy:relay:dry-run
```

Agent validation:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bun run lint:agent
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bun run test:agent
```

`bun run build:agent` produces the release CLI, daemon, and SleepHold artifacts, then embeds
them in the release `Cicada.app` under `Contents/Helpers`. It does not install into
`~/.cicada/bin` or replace `/Applications/Cicada.app`.

## Deploy

Cloudflare supports Wrangler on Node only. Confirm Node 24 is installed (`node --version`) before
running the commands below; without Node, `bun run` silently runs Wrangler on Bun instead.

Upload a version without moving production traffic:

```bash
bun run --cwd apps/relay wrangler versions upload
bun run --cwd apps/relay wrangler versions list
```

Record the new version ID and the currently active version ID. Where gradual deployments are
available, deploy the new version with a small percentage first and increase it only after the
smoke checks and observability checks pass. Otherwise, use `wrangler deploy` and keep the previous
version ID ready for immediate rollback.

```bash
bun run --cwd apps/relay wrangler deploy
bun run --cwd apps/relay wrangler deployments list
```

Never deploy from a dirty worktree. Production deployment requires an explicit operator decision;
the validation commands in this runbook do not authorize one.

## Enrolling a new Mac

A device ID that has no bound identity key can only register for the first time with a one-time
enrollment code. Issuing codes needs `CICADA_ADMIN_TOKEN` (set it as described below); without the
secret no new device can enroll. Issue a code right before setting up the Mac, using placeholder
values only in saved examples:

```bash
curl -X POST 'https://relay.example.com/v1/admin/enrollment-codes' \
  -H 'Authorization: Bearer <ADMIN_TOKEN>'
```

The response `{"ok":true,"enrollmentCode":"cicada_enroll_...","expiresAt":...}` is the only place
the code appears. It is valid for 10 minutes, works once, and Relay stores only its hash. Give it to
the Mac agent for its first connection; afterwards the device ID stays bound to that agent's key and
later connections need no code. Devices bound before this release are not affected. Failure codes
and the wire format are in [Agent Registration](../../packages/shared/COMMANDS.md#agent-registration).

The Mac agent does not send enrollment codes yet; that support ships separately. Until it does, only
devices bound before this release can connect, and a device that is reset cannot register again, so
do not reset devices in the meantime.

## Administrator device recovery

`CICADA_ADMIN_TOKEN` is an optional administrator **secret**. It is required by
`POST /v1/admin/enrollment-codes`, `POST /v1/admin/device-reset`, `GET /devices`, and
`GET /status?device_id=...`; without it these endpoints return 404. `POST /v1/admin/device-reset`
clears a device's identity binding and is the only recovery path when a Mac is replaced or
reinstalled, or its identity key is lost or rotated.

Run from the monorepo root and enter the secret at Wrangler's interactive prompt;
never put it in `wrangler.toml` or `.dev.vars.example`:

```bash
bun run --cwd apps/relay wrangler secret put CICADA_ADMIN_TOKEN
```

To rotate the token, run the same command with a new value and update the
administrator's Bearer credential. To delete the secret and disable these endpoints:

```bash
bun run --cwd apps/relay wrangler secret delete CICADA_ADMIN_TOKEN
```

After a reset the device ID is unbound: its old key no longer connects, and the
Mac must enroll again with a new enrollment code. Without a valid code no other
agent can claim the device ID.

Use placeholder values only in saved examples; replace the token and device ID
for the actual request:

```bash
curl -X POST 'https://relay.example.com/v1/admin/device-reset' \
  -H 'Authorization: Bearer <ADMIN_TOKEN>' \
  -H 'Content-Type: application/json' \
  --data '{"device_id":"MAC_0123456789ABCDEF0123456789ABCDEF"}'
```

Expected success response:

```json
{"ok":true,"deviceId":"MAC_0123456789ABCDEF0123456789ABCDEF","existed":true}
```

`existed` indicates whether a registry entry was removed (false means none
existed). With the secret configured, a missing or incorrect Bearer token returns
401; malformed JSON or an invalid `device_id` returns 400. A valid device ID is
`MAC_` followed by 32 hexadecimal characters. After success, issue a new
enrollment code, enroll the Mac again, and confirm `/status?device_id=...` for that
device with the administrator token.

## Smoke

1. Start `wrangler dev` or a preview deployment.
2. Start a Swift agent; it should connect to `GET /relay/:liveSession`. On a fresh registry the
   agent first needs an enrollment code (see [Enrolling a new Mac](#enrolling-a-new-mac)).
3. Confirm `/devices` shows one online device and `/status?device_id=MAC_...` matches it. Both
   need the administrator token:

```bash
curl 'https://relay.example.com/devices' -H 'Authorization: Bearer <ADMIN_TOKEN>'
curl 'https://relay.example.com/status?device_id=MAC_...' -H 'Authorization: Bearer <ADMIN_TOKEN>'
```

   Without the header they return 401; when `CICADA_ADMIN_TOKEN` is not set they return 404.
4. On the agent machine, create a Shortcuts grant:

```bash
cicada shortcut create --name iPhone --commands ping,status --ttl 30d
```

5. In iOS Shortcuts, create **Get Contents of URL**:

```text
POST https://relay.example.com/v1/shortcuts/command
Authorization: Bearer cicada_sc_<token>
Content-Type: application/json
{"device_id":"MAC_...","command":"ping","request_id":"shortcut-ping"}
```

6. Confirm the Shortcut receives `ok:true`, `success:true`, and `message:"pong"`.
7. Revoke the token with `cicada shortcut revoke <grantId>` and confirm the same Shortcut returns `grant_revoked`.
8. Stop the agent and confirm the Shortcut returns `agent_unavailable`; commands must not be queued.

9. Send a request with a caller-supplied `X-Request-ID`. Confirm the response and structured
   completion log use the same ID. Do not deliberately generate a production 5xx.

## Log and alert checks

Follow [Relay Observability Runbook](relay-observability.md). Confirm normal request completion,
WebSocket upgrade outcome, Durable Object operation, and request-ID correlation are visible. Verify
that no Authorization value, session secret, nonce, signature, token hash, or complete Shortcuts
payload appears in sampled logs.

## Rollback

Rollback is a production action and requires operator approval. Identify the last known-good
version before running:

```bash
bun run --cwd apps/relay wrangler deployments list
bun run --cwd apps/relay wrangler versions list
bun run --cwd apps/relay wrangler rollback <LAST_KNOWN_GOOD_VERSION_ID>
```

Repeat the smoke and log checks after rollback. Stages 1–6 preserve the Durable Object class name,
binding, storage keys, and serialized schema, so they require no reverse data migration. If a future
release changes Durable Object storage, stop here and follow its dedicated migration and dual-read
rollback plan instead of using an unconditional Worker rollback.

The enrollment-code release only adds the registry key `enrollment_codes`; earlier versions ignore
it and keep every existing binding, so rolling back needs no migration. A rolled-back Relay accepts
first registration without a code again, so roll forward as soon as possible.

## Agent and DMG rollback

Relay-only changes do not require a DMG rebuild. For a Native change, rebuild the app, verify bundled
helpers and code signatures, verify the DMG, and retain the prior signed DMG. Roll back by restoring
the prior signed app/DMG and restarting the existing launchd service; do not mix an agent rollback
with a Relay schema change. Re-run agent status, IPC, reconnect, and command smoke checks.

## Exercise record

For each release or rollback exercise, record commit, Worker version IDs, operator, timestamps,
smoke results, alert delivery result, and Durable Object compatibility conclusion. A dry-run or a
written command is not evidence that a production rollback exercise occurred.

## Protocol Checks

- Agent registrations fail closed when the registry rejects the enrollment code, identity binding, signature, timestamp, or nonce.
- `shortcut_grant_update` publishes only token hash/preview, never the full token.
- Logs must not contain Authorization, `cicada_sc_` tokens, enrollment codes, token hashes, nonces, signatures, or shortcut payloads.
