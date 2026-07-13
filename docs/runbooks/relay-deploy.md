# Relay Deploy Runbook

## Preflight

From the monorepo root:

```bash
pnpm run build:relay
pnpm run lint:relay
pnpm run test:relay
pnpm --filter @cicada/relay exec jest --coverage --silent
pnpm run deploy:relay:dry-run
```

Agent validation:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer pnpm run lint:agent
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer pnpm run test:agent
```

`pnpm run build:agent` produces the release CLI, daemon, and SleepHold artifacts, then embeds
them in the release `Cicada.app` under `Contents/Helpers`. It does not install into
`~/.cicada/bin` or replace `/Applications/Cicada.app`.

## Deploy

Upload a version without moving production traffic:

```bash
pnpm --filter @cicada/relay exec wrangler versions upload
pnpm --filter @cicada/relay exec wrangler versions list
```

Record the new version ID and the currently active version ID. Where gradual deployments are
available, deploy the new version with a small percentage first and increase it only after the
smoke checks and observability checks pass. Otherwise, use `wrangler deploy` and keep the previous
version ID ready for immediate rollback.

```bash
pnpm --filter @cicada/relay exec wrangler deploy
pnpm --filter @cicada/relay exec wrangler deployments list
```

Never deploy from a dirty worktree. Production deployment requires an explicit operator decision;
the validation commands in this runbook do not authorize one.

## Smoke

1. Start `wrangler dev` or a preview deployment.
2. Start a Swift agent; it should connect to `GET /relay/:liveSession`.
3. Confirm `/devices` shows one online device and `/status?device_id=MAC_...` matches it.
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
pnpm --filter @cicada/relay exec wrangler deployments list
pnpm --filter @cicada/relay exec wrangler versions list
pnpm --filter @cicada/relay exec wrangler rollback <LAST_KNOWN_GOOD_VERSION_ID>
```

Repeat the smoke and log checks after rollback. Stages 1–6 preserve the Durable Object class name,
binding, storage keys, and serialized schema, so they require no reverse data migration. If a future
release changes Durable Object storage, stop here and follow its dedicated migration and dual-read
rollback plan instead of using an unconditional Worker rollback.

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

- Agent registrations fail closed when the registry rejects identity binding, signature, timestamp, or nonce.
- `shortcut_grant_update` publishes only token hash/preview, never the full token.
- Logs must not contain Authorization, `cicada_sc_` tokens, token hashes, nonces, signatures, or shortcut payloads.
