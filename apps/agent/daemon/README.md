# Cicada Daemon（Swift）

`cicada-agent` 是 Cicada 的 Swift 常驻进程，负责：

1. 与 CicadaRelay 建立 WebSocket 长连接（保持现有协议）
2. 接收远程命令并在本机执行
3. 通过 UDS 将结果发送到 `cicada-notifier`

## 配置文件

守护进程读取：

`~/.cicada/config.json`

最小配置示例：

```json
{
  "relayURL": "https://your-cicada-relay.workers.dev",
  "deviceId": "MAC_0123456789ABCDEF0123456789ABCDEF",
  "apiKey": "your-api-key",
  "autoConnect": true,
  "showNotifications": true,
  "enableAutoReconnect": true,
  "reconnectInterval": 5000,
  "maxReconnectAttempts": 10,
  "heartbeatInterval": 30000,
  "connectionTimeout": 10000
}
```

配置语义（收敛后）：

| 字段 | 是否生效 | 生效点 |
|---|---|---|
| `relayURL` | 是 | WebSocket 连接地址构造 |
| `deviceId` | 是 | `/ws` 查询参数 `device_id` |
| `apiKey` | 是 | `/ws` 查询参数 `api_key` |
| `autoConnect` | 是 | `start()` 阶段决定 `connected` / `idle` |
| `showNotifications` | 是 | 命令执行后与连接成功提示是否通知 |
| `enableAutoReconnect` | 是 | 断连后是否进入重连调度 |
| `reconnectInterval` | 是 | 重连基础退避时间（ms） |
| `maxReconnectAttempts` | 是 | 最大重连次数（`0` 表示不限制） |
| `heartbeatInterval` | 是 | ping 周期（ms） |
| `connectionTimeout` | 是 | URLSession 超时与 pong 健康检查（ms） |

## 安装与管理

推荐通过 CLI：

```bash
~/.cicada/bin/cicada daemon install
~/.cicada/bin/cicada daemon start
~/.cicada/bin/cicada daemon stop
~/.cicada/bin/cicada daemon restart
~/.cicada/bin/cicada daemon status
~/.cicada/bin/cicada daemon logs
```

推荐配置与重启顺序：

```bash
~/.cicada/bin/cicada config set autoConnect true
~/.cicada/bin/cicada config set showNotifications true
~/.cicada/bin/cicada config set connectionTimeout 10000
~/.cicada/bin/cicada daemon restart
~/.cicada/bin/cicada doctor
```

## LaunchAgent

1. Label: `com.cicada.agent`
2. plist: `~/Library/LaunchAgents/com.cicada.agent.plist`
3. binary: `~/.cicada/bin/cicada-agent`

## 日志

1. `~/.cicada/daemon.log`
2. `~/.cicada/daemon.stdout.log`
3. `~/.cicada/daemon.stderr.log`
4. `~/.cicada/daemon.state.json`
