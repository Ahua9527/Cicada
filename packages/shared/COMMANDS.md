# Cicada Command And Shortcuts Contract

`packages/shared` owns the public Relay contract. Cicada no longer exposes a
separate controller role. iOS control is Shortcuts HTTP API; the Mac agent keeps
one WebSocket session open to Relay.

## Current Commands

<!-- commands:begin -->
<!-- 自动生成，改命令后运行 bun run protocol:generate -->
| Command | Description |
|---|---|
| `lock` | 锁定屏幕 |
| `bt_toggle` | 切换蓝牙状态 |
| `ping` | 连接测试 |
| `volume_mute` | 静音/取消静音 |
| `sleep` | 系统休眠 |
| `sleep_displays` | 显示器休眠 |
| `caffeinate` | 保持唤醒 |
| `decaffeinate` | 允许休眠 |
| `status` | 获取设备状态 |
| `sentry_start` | 启动哨兵 |
| `sentry_stop` | 停止哨兵 |
| `sentry_status` | 获取哨兵状态 |
| `sentry_unlock` | 解除哨兵告警 |
| `sentry_open` | 打开哨兵窗口 |
| `wake` | 唤醒显示器 |
| `restart` | 重启系统 |
| `shutdown` | 关机 |
| `bt_on` | 开启蓝牙 |
| `bt_off` | 关闭蓝牙 |
| `bt_status` | 获取蓝牙状态 |
| `brightness_up` | 调高亮度 |
| `brightness_down` | 调低亮度 |
| `brightness_set` | 设置亮度 |
| `screenshot` | 截屏 |
| `mute` | 静音 |
| `unmute` | 取消静音 |
| `volume_up` | 调高音量 |
| `volume_down` | 调低音量 |
| `volume_set` | 设置音量 |
| `app_open` | 打开应用 |
| `app_close` | 关闭应用 |
| `app_switch` | 切换到应用 |
| `app_list` | 列出运行中应用 |
| `daemon_exit` | 退出远程控制服务 |
<!-- commands:end -->

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

## Agent WebSocket Messages

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

Do not use `bun run build:agent` as a routine check; it installs binaries into
`~/.cicada/bin`.
