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

Do not run `pnpm run build:agent` as a routine check; it installs binaries into
`~/.cicada/bin`.

## Deploy

```bash
pnpm --filter @cicada/relay exec wrangler deploy
```

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

## Protocol Checks

- Agent registrations fail closed when the registry rejects identity binding, signature, timestamp, or nonce.
- `shortcut_grant_update` publishes only token hash/preview, never the full token.
- Logs must not contain Authorization, `cicada_sc_` tokens, token hashes, nonces, signatures, or shortcut payloads.
