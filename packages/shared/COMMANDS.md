# Cicada Command And Shortcuts Contract

`packages/shared` owns the public Relay contract. Cicada no longer exposes a
separate controller role. iOS control is Shortcuts HTTP API; the Mac agent keeps
one WebSocket session open to Relay.

## Current Commands

<!-- commands:begin -->
<!-- 自动生成，改命令后运行 bun run protocol:generate -->
| Command | Description | Risk |
|---|---|---|
| `lock` | 锁定屏幕 |  |
| `bt_toggle` | 切换蓝牙状态 |  |
| `ping` | 连接测试 |  |
| `volume_mute` | 静音/取消静音 |  |
| `sleep` | 系统休眠 | 高风险 |
| `sleep_displays` | 显示器休眠 |  |
| `caffeinate` | 保持唤醒 |  |
| `decaffeinate` | 允许休眠 |  |
| `status` | 获取设备状态 |  |
| `sentry_start` | 启动哨兵 |  |
| `sentry_stop` | 停止哨兵 | 高风险 |
| `sentry_status` | 获取哨兵状态 |  |
| `sentry_unlock` | 解除哨兵告警 | 高风险 |
| `sentry_open` | 打开哨兵窗口 |  |
| `wake` | 唤醒显示器 |  |
| `restart` | 重启系统 | 高风险 |
| `shutdown` | 关机 | 高风险 |
| `bt_on` | 开启蓝牙 |  |
| `bt_off` | 关闭蓝牙 |  |
| `bt_status` | 获取蓝牙状态 |  |
| `brightness_up` | 调高亮度 |  |
| `brightness_down` | 调低亮度 |  |
| `brightness_set` | 设置亮度 |  |
| `screenshot` | 截屏 | 高风险 |
| `mute` | 静音 |  |
| `unmute` | 取消静音 |  |
| `volume_up` | 调高音量 |  |
| `volume_down` | 调低音量 |  |
| `volume_set` | 设置音量 |  |
| `app_open` | 打开应用 |  |
| `app_close` | 关闭应用 | 高风险 |
| `app_switch` | 切换到应用 |  |
| `app_list` | 列出运行中应用 |  |
| `daemon_exit` | 退出远程控制服务 | 高风险 |
<!-- commands:end -->

Commands marked 高风险 (high risk) are listed in `HIGH_RISK_COMMANDS` and in
`high_risk_commands` of `protocol/command-contract.json`. `cicada shortcut create --commands all`
grants every command except these; name a high-risk command explicitly to grant it, for
example `--commands all,shutdown`. Existing grants keep their stored command list.

Mac agent command execution is native Swift/macOS API code. The command path
does not require installed shell utilities or third-party binaries. Bluetooth
power control uses a vendored source bridge based on the open-source
`toy/blueutil` technique, compiled into Cicada instead of shelling out to a
binary. No-sleep mode uses a native IOPM assertion and can additionally use the
vendored `Lakr233/SleepHoldService` session model through Cicada's own
`cicada-sleephold` helper for lid-close sleep prevention. Permission-sensitive
commands fail closed with a clear error.

Sentinel commands are routed through the Cicada daemon to the local Sentinel
app IPC socket. `sentry_start` starts the migrated Sentry runtime, including
trigger monitoring, Bark notification, recording, and daemon-backed no-sleep
assertions.

## Mac CLI Flow

Daily use is intentionally small:

```bash
cicada setup --relay-url https://relay.example.com
cicada start
cicada shortcut create
cicada status
cicada run ping
```

`cicada shortcut create` creates the iOS Shortcuts capability token and prints
the URL, Authorization header, and JSON body template needed by Shortcuts. The
full token is shown only once. Troubleshooting commands live under
`cicada advanced ...` and are not part of the normal user flow.

SleepHold helper management is intentionally advanced-only:

```bash
cicada advanced sleep install
cicada advanced sleep status
cicada advanced sleep ping
cicada advanced sleep create
cicada advanced sleep extend <sessionId>
cicada advanced sleep terminate <sessionId>
cicada advanced sleep uninstall
```

## Agent Registration

The Mac agent connects with a WebSocket upgrade to `GET /relay/<liveSessionId>` and registers in
the request headers:

| Header | Value |
|---|---|
| `x-device-id` | `MAC_` followed by 32 hexadecimal characters |
| `x-agent-identity-public-key` | Ed25519 public key: the raw 32 bytes in standard base64 |
| `x-agent-registration-timestamp` | Unix time in milliseconds; Relay accepts ±90 seconds |
| `x-agent-registration-nonce` | Random string; each value is accepted once per device |
| `x-agent-registration-signature` | Ed25519 signature over the transcript below, standard base64 |
| `x-agent-enrollment-code` | One-time enrollment code; only while the device ID is not bound yet |

The signed transcript is the fields below in this order, each encoded as UTF-8 and preceded by its
byte length as a 4-byte big-endian unsigned integer:

| # | v1 (no enrollment code) | v2 (with `x-agent-enrollment-code`) |
|---|---|---|
| 1 | `cicada-agent-registration-v1` | `cicada-agent-registration-v2` |
| 2 | device ID | device ID |
| 3 | live session ID (the `/relay/<id>` path segment) | live session ID |
| 4 | identity public key, exactly as sent in the header | identity public key |
| 5 | timestamp as a decimal string | timestamp |
| 6 | nonce | nonce |
| 7 | — | enrollment code, exactly as issued |

1. A device ID with no bound key must send `x-agent-enrollment-code` and sign v2. Relay verifies
   the signature with the presented key, consumes the code, and binds the device ID to that key
   permanently.
2. A bound device without the code header signs v1, unchanged from before enrollment codes.
3. A bound device that still sends the code header signs v2 with its bound key. Relay does not
   check or consume the code again, so a reconnect after a lost success response still works. The
   agent should stop sending the code after its first successful connection.
4. A replaced or reinstalled Mac has a new key: clear the binding with
   `POST /v1/admin/device-reset`, then enroll again with a new code.

The administrator issues codes with `POST /v1/admin/enrollment-codes` and
`Authorization: Bearer <CICADA_ADMIN_TOKEN>`. The response
`{"ok":true,"enrollmentCode":"cicada_enroll_<22 base64url characters>","expiresAt":<unix ms>}` is
the only place the code appears; Relay stores only its SHA-256 hash. A code is valid for 10
minutes, works once, and is not tied to a device ID in advance. Trim surrounding whitespace before
signing and sending it, because HTTP strips it from header values.

A rejected registration answers the upgrade with HTTP 429 and
`{"success":false,"error":"...","code":"..."}`:

| Code | Meaning |
|---|---|
| `agent_enrollment_code_required` | Unbound device ID without `x-agent-enrollment-code` |
| `agent_enrollment_code_invalid` | Code was never issued, or was already pruned |
| `agent_enrollment_code_expired` | Code is older than 10 minutes |
| `agent_enrollment_code_used` | Code already enrolled a device |
| `agent_registration_signature_required` | Timestamp, nonce, or signature header is missing |
| `agent_registration_expired` | Timestamp is outside ±90 seconds |
| `agent_registration_replayed` | Nonce was already used |
| `invalid_agent_registration_signature` | Signature does not match the presented key and transcript |
| `agent_identity_mismatch` | Device ID is bound to a different key |

`protocol/fixtures/agent_enrollment.json` is a complete first registration: the headers, the
ordered v2 transcript fields, and the transcript bytes in base64. Its key pair was generated only
for the fixture and the private key was discarded. Relay tests check that the fields, bytes, and
signature agree and that Relay accepts the request; a Swift transcript builder must reproduce the
same bytes from the same fields.

## Agent WebSocket Messages

Shared wire examples live in `packages/shared/protocol/fixtures/`: `shortcut_command.json`,
`shortcut_result_success.json`, `shortcut_result_failure.json`, `shortcut_grant_update.json`,
and `shortcut_grant_update_ack.json`. Relay integration tests and Swift `RelayMessageCodec`
tests both read these files and check field names and values against the actual messages.
Missing fixtures fail the tests; field renames must be coordinated across both languages.
Request IDs and timestamps are normalized where generated dynamically. All token values are fake.

Visible Relay envelopes:

```json
{"type":"hello","from":"agent","sent_at":1704067200000}
{"type":"shortcut_grant_update","from":"agent","sent_at":1704067200000,"data":{"state":"active","grant":{"grantId":"grant-1","deviceId":"MAC_...","name":"iPhone","tokenHash":"base64url","tokenPreview":"cicada_sc_ab...1234","allowedCommands":["ping","status"],"expiresAt":1706659200000,"createdAt":1704067200000,"updatedAt":1704067200000}}}
{"type":"shortcut_grant_update_ack","ok":true,"grantId":"grant-1","state":"active","sent_at":1704067200001}
{"type":"shortcut_command","id":"req-1","sent_at":1704067200000,"data":{"requestId":"req-1","grantId":"grant-1","command":"ping"}}
{"type":"shortcut_result","id":"req-1","from":"agent","sent_at":1704067200001,"data":{"requestId":"req-1","command":"ping","ok":true,"success":true,"message":"pong"}}
{"type":"ping","id":"ping-1","sent_at":1704067200000}
{"type":"pong","id":"ping-1","sent_at":1704067200001}
{"type":"error","code":"agent_unavailable","error":"Agent is not connected.","sent_at":1704067200001}
```

Close codes:

| Code | Name | Meaning |
|---|---|---|
| `4000` | `INVALID_SESSION_OR_ROLE` | Invalid relay target or removed role |
| `4001` | `AGENT_REPLACED` | Previous agent socket was replaced |
| `4002` | `AGENT_UNAVAILABLE` | Agent is unavailable |
| `4004` | `AGENT_TEMPORARILY_UNAVAILABLE` | Reserved for temporary agent absence |

## Shortcuts HTTP API

```http
POST /v1/shortcuts/command
Authorization: Bearer cicada_sc_<token>
Content-Type: application/json
```

```json
{"device_id":"MAC_...","command":"ping","request_id":"optional"}
```

Response:

```json
{"ok":true,"request_id":"req-1","command":"ping","success":true,"message":"pong","timestamp":1704067200001}
```

Failure codes include `invalid_token`, `grant_expired`, `grant_revoked`,
`command_not_allowed`, `agent_unavailable`, and `command_timeout`.

## Authoritative Files

1. `src/types/relay-transport.types.ts`
2. `src/protocol/commands.ts`
3. `src/types/command.types.ts`
4. `src/validators/command.validator.ts`
5. `apps/agent/swift/Sources/CicadaCore/Models.swift`
6. `apps/agent/swift/Sources/CicadaCore/ShortcutGrant.swift`

## Validation

```bash
bun run build:relay
bun run lint:relay
bun run test:relay
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bun run lint:agent
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bun run test:agent
```

`bun run build:agent` builds the release CLI, daemon, and SleepHold helper, then
builds `Cicada.app` and embeds those helpers under `Contents/Helpers`. The app
artifact is in `apps/agent/native/sentinel-app/.build/DerivedData/Build/Products/Release/`
with the default configuration. This command does not install into `~/.cicada/bin`
or replace `/Applications/Cicada.app`.
