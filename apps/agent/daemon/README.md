# Cicada Daemon（Swift）

`cicada-agent` 是 Cicada 的 Swift 常驻进程，负责：

1. 与 CicadaRelay 建立 agent WebSocket 长连接
2. 发布 Shortcuts capability grants
3. 接收 `shortcut_command` 并在本机执行
4. 通过 UDS 将结果发送到 Sentinel 内置 notifier socket
5. 可选安装 root `cicada-sleephold` helper，用于合盖防睡眠

## 配置文件

守护进程读取：

`~/.cicada/config.json`

最小配置示例：

```json
{
  "relayURL": "https://your-cicada-relay.workers.dev",
  "deviceId": "MAC_0123456789ABCDEF0123456789ABCDEF",
  "autoConnect": true,
  "showNotifications": true,
  "enableAutoReconnect": true,
  "reconnectInterval": 5000,
  "maxReconnectAttempts": 10,
  "heartbeatInterval": 30000,
  "connectionTimeout": 10000
}
```

## 用户流程

```bash
~/.cicada/bin/cicada setup --relay-url https://your-cicada-relay.workers.dev
~/.cicada/bin/cicada start
~/.cicada/bin/cicada shortcut create
~/.cicada/bin/cicada status
~/.cicada/bin/cicada run ping
```

## CLI 能力边界

| 命令 | 能力边界 |
|---|---|
| `cicada setup [--relay-url <url>]` | 创建或更新 `~/.cicada/config.json`，生成 `deviceId`，写入 Relay URL；不启动 daemon。 |
| `cicada start` | 安装缺失的 daemon/Sentinel 并启动本机 agent 服务；daemon 自动连接 Relay。 |
| `cicada stop` / `cicada restart` | 停止或重启 daemon/Sentinel。 |
| `cicada status [--json]` | 合并 config、daemon、Sentinel、runtime snapshot 和原生权限/能力摘要；不是完整端到端网络 smoke。 |
| `cicada shortcut create [--name <name>] [--commands <csv|all>] [--ttl <duration>]` | 创建 iOS Shortcuts token，默认授权 `ping,status`、30 天；完整 token 只显示一次。 |
| `cicada shortcut list` / `cicada shortcut revoke <id>` | 查看或撤销 Shortcuts token；通过 `~/.cicada/run/daemon.sock` 请求 daemon，daemon 不运行时失败。 |
| `cicada run <command>` | 本机直接执行 9 个 Mac 命令，用于测试和手动操作；绕过 Relay 与 Shortcuts token。 |

排障入口集中在 `advanced` 下：

```bash
cicada advanced config get|set|validate|path
cicada advanced daemon install|start|stop|restart|status|uninstall|logs
cicada advanced sleep install|uninstall|status|ping|create|extend|terminate
cicada advanced doctor --json
```

## Mac 命令边界

| 命令 | 能力边界 |
|---|---|
| `lock` | 使用 CoreGraphics/Accessibility 发送系统锁屏快捷动作；缺少辅助功能权限时失败关闭。 |
| `bt_toggle` | 使用 vendored Bluetooth source bridge 切换本机 Bluetooth power；不要求安装第三方命令行工具，缺少蓝牙权限时失败关闭。 |
| `ping` | 返回 `pong`，用于 smoke。 |
| `volume_mute` | 使用 CoreAudio 切换默认输出设备静音；失败时返回错误，不执行脚本回退。 |
| `sleep` | 使用 IOKit power management 让系统睡眠；失败时返回错误，不执行外部命令回退。 |
| `sleep_displays` | 使用 IOKit display idle request 让显示器睡眠；失败时返回错误。 |
| `caffeinate` | daemon 持有 IOPM no-sleep assertion；如果 `cicada-sleephold` 已安装运行，同时创建并自动续租合盖防睡眠 session。CLI 入口通过本机 daemon socket 请求，daemon 未运行时失败。 |
| `decaffeinate` | daemon 释放自身 IOPM no-sleep assertion，并终止自身持有的 SleepHold session；不终止同用户其他进程。 |
| `status` | 返回 uptime、电量、蓝牙状态；蓝牙权限或 bridge 不可用时蓝牙显示“未知”。 |

Mac 命令执行层不依赖外部二进制；不要求安装 Homebrew、MacPorts、`blueutil`、shell 脚本或系统命令包装器。Bluetooth power 切换源码桥参考 `toy/blueutil` 的 MIT 许可实现，源码随 agent 编译。合盖防睡眠能力参考 `Lakr233/SleepHoldService` 的 MIT 许可实现，源码随 agent 编译为 `cicada-sleephold`。`lock` 和 `bt_toggle` 受 macOS TCC 权限控制，权限不足时按 fail-closed 返回明确错误。

## SleepHold Helper

`cicada-sleephold` 是可选 root LaunchDaemon，用于覆盖普通 IOPM assertion
无法保证的“合盖仍不睡眠”场景。日常命令树不自动安装它；需要时显式执行：

```bash
cicada advanced sleep install
cicada advanced sleep status
```

安装后：

1. LaunchDaemon: `/Library/LaunchDaemons/com.cicada.sleephold.plist`
2. Binary: `/usr/local/sbin/cicada-sleephold`
3. Local socket: `~/.cicada/run/sleephold.sock`

`apps/agent/scripts/build.sh` 会把 helper 先放到
`~/.cicada/bin/cicada-sleephold`；`cicada advanced sleep install` 再通过
管理员权限安装到 `/usr/local/sbin/cicada-sleephold`。

完整控制能力：

```bash
cicada advanced sleep ping
cicada advanced sleep create
cicada advanced sleep extend <sessionId>
cicada advanced sleep terminate <sessionId>
cicada advanced sleep uninstall
```

每个 SleepHold session 默认 30 秒租约；daemon 执行 `caffeinate` 后会每
15 秒续租，`decaffeinate` 或租约过期会恢复系统可睡眠状态。

## Shortcuts Grants

agent daemon 在线后，在 Mac 上创建 Shortcuts token：

```bash
~/.cicada/bin/cicada shortcut create --name iPhone --commands ping,status --ttl 30d
```

输出包含完整 token，且只显示这一次：

```json
{
  "ok": true,
  "shortcutToken": "cicada_sc_xxx",
  "shortcutGrant": {
    "grantId": "grant-...",
    "tokenPreview": "cicada_sc_xx...1234",
    "allowedCommands": ["ping", "status"]
  }
}
```

完整 token 不写入 `daemon.log`、stdout/stderr 持久日志、`daemon.state.json`
或 Relay registry。agent 和 Relay 只保存 token hash 与 preview。

管理命令：

```bash
~/.cicada/bin/cicada shortcut list
~/.cicada/bin/cicada shortcut revoke <grantId>
```

默认命令范围是 `ping,status`。需要授权全部 9 个命令时显式使用
`--commands all`。

## iOS Shortcuts

使用 **Get Contents of URL**：

```text
URL: https://relay.example.com/v1/shortcuts/command
Method: POST
Headers:
  Authorization: Bearer cicada_sc_<token>
  Content-Type: application/json
Body:
  {"device_id":"MAC_...","command":"ping","request_id":"shortcut-ping"}
```

读取响应里的 `ok`、`success`、`message` 和可选 `data`。

## LaunchAgent

1. Label: `com.cicada.agent`
2. plist: `~/Library/LaunchAgents/com.cicada.agent.plist`
3. binary: `~/.cicada/bin/cicada-agent`

## 日志

1. `~/.cicada/daemon.log`
2. `~/.cicada/daemon.stdout.log`
3. `~/.cicada/daemon.stderr.log`
4. `~/.cicada/daemon.state.json`
5. 本机控制 socket: `~/.cicada/run/daemon.sock`
