# Relay Observability Runbook

## Event contract

Relay emits JSON logs to the Cloudflare Workers runtime. Request events use these stable fields:

| Field | Meaning |
|---|---|
| `request_id` | Correlation ID returned as `X-Request-ID` on failures. |
| `route` | Normalized route; live session identifiers are replaced by `:liveSession`. |
| `status` | HTTP status, including WebSocket `101`. |
| `error_type` | `client_error`, `server_error`, or the caught error class. |
| `duration_ms` | Worker-side request duration in milliseconds. |
| `do_operation` | Durable Object operation reached by the public route. |
| `websocket_outcome` | `upgraded` or `upgrade_failed`. |

The logger filters credential-like keys recursively. Do not add raw request bodies, Authorization
headers, session secrets, nonces, signatures, token hashes, or complete Shortcuts payloads to log
contexts. An error stack is retained after credential text is redacted.

## Live diagnosis

Use a narrow time window and filter by the request ID supplied by the caller:

```bash
pnpm --filter @cicada/relay exec wrangler tail --format json
```

In Workers Observability or the Logpush destination, filter `request_id` first, then inspect
`route`, `status`, `error_type`, `do_operation`, and `websocket_outcome`. A healthy HTTP request has
one completion event. A successful agent upgrade has `status=101` and
`websocket_outcome=upgraded`.

## Alert definitions

Create alerts from the same event contract in Cloudflare Workers Observability, or in the existing
Logpush destination. Use five-minute rolling windows:

| Alert | Initial condition |
|---|---|
| Relay 5xx | At least 20 requests with `status >= 500`, and more than 1% of requests. |
| WebSocket upgrade failures | At least 20 events with `websocket_outcome=upgrade_failed`, and more than 5% of WebSocket upgrade attempts. |
| Durable Object exceptions | More than 5 error events with `do_operation` present. |
| Replay rejection spike | Replay/nonce rejection count is at least 3 times the same weekday/time baseline. |
| Rate-limit spike | `status=429` count is at least 3 times the same weekday/time baseline. |

Route alerts to the normal on-call destination. Keep event definitions fixed for the first seven
days; after collecting a production baseline, adjust only thresholds. Record the alert policy ID,
notification destination, owner, creation date, and last test date in the operations system.

## Safe alert test

Do not inject failures into production. Use a preview deployment or local `wrangler dev`, run the
automated public-error boundary test, and confirm its synthetic request ID appears in the selected
log pipeline. For an end-to-end alert test, temporarily point a copy of the policy at preview logs,
lower its threshold, verify delivery, then restore or delete the copy. Record the test result; do
not change the production event definition.

## Tail and Logpush retention

Workers Tail is for immediate diagnosis, not retention. Configure Cloudflare Logpush when durable
history or aggregate alerting is required. The destination must enforce restricted access and a
retention period appropriate for operational logs. Before enabling a new field, inspect sample
events and prove that secrets and complete sensitive payloads are absent.
