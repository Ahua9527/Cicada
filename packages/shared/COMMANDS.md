# 权威命令列表

> 命令契约单源：`packages/shared`

## 当前命令（9）

| 命令 | 描述 |
|---|---|
| `lock` | 锁定屏幕 |
| `bt_toggle` | 切换蓝牙 |
| `ping` | 连通性测试 |
| `volume_mute` | 静音切换 |
| `sleep` | 系统休眠 |
| `sleep_displays` | 显示器休眠 |
| `caffeinate` | 启用防休眠 |
| `decaffeinate` | 关闭防休眠 |
| `status` | 获取设备状态 |

## 权威文件

1. `src/types/command.types.ts`
2. `src/validators/command.validator.ts`

## 变更规则

1. 命令变更必须同时修改上述两个文件。
2. 命令变更必须同步更新本文件。
3. 不允许在 `apps/relay` 或 `apps/agent` 内维护 shared 副本。

## 变更后验证

### CicadaRelay

```bash
cd /path/to/Cicada
pnpm run build:relay
pnpm run lint:relay
pnpm run test:relay
```

### Cicada

当命令集合变化时，对齐 Swift 侧：

1. `apps/agent/swift/Sources/CicadaCore/Models.swift`
2. `apps/agent/swift/Sources/CicadaSystem/MacOSCommandGateway.swift`

并执行：

```bash
cd /path/to/Cicada
pnpm run lint:agent
pnpm run test:agent
pnpm run build:agent
```

## 目录约束

1. `packages/shared` 是唯一契约目录。
2. Relay 通过 `@cicada/shared` workspace 依赖使用契约。
3. Swift 侧按本文件同步命令集合，不引入第二份 TypeScript shared 副本。
