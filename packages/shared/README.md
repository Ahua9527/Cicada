# @cicada/shared

Cicada 系统的共享契约层，包含命令类型、验证规则与通用类型工具。

## 定位

`@cicada/shared` 是命令契约的唯一来源（Single Source of Truth）：

1. 命令类型：`src/types/command.types.ts`
2. 命令验证：`src/validators/command.validator.ts`
3. 共享导出：`src/index.ts`

## 治理约束

1. 本包只在 monorepo 根目录 `packages/shared` 维护。
2. Relay 通过 workspace 依赖 `@cicada/shared` 使用本包。
3. 不维护镜像目录、同步脚本或双仓库副本。
4. 变更契约后，必须同步评估 Cicada Swift 侧实现。

## 目录

```text
packages/shared/
├── src/
│   ├── types/
│   ├── validators/
│   ├── errors/
│   ├── logger/
│   ├── constants.ts
│   ├── utils.ts
│   └── index.ts
├── COMMANDS.md
├── package.json
└── tsconfig.json
```

## 开发命令

```bash
cd /path/to/Cicada/packages/shared
pnpm run build
pnpm run dev
pnpm run clean
```

## 变更流程

### 1. 修改契约

至少同时更新：

1. `src/types/command.types.ts`
2. `src/validators/command.validator.ts`
3. `COMMANDS.md`

### 2. 验证 CicadaRelay

```bash
cd /path/to/Cicada
pnpm run build:relay
pnpm run lint:relay
pnpm run test:relay
```

### 3. 对齐 Cicada Swift

当命令集合发生变化时，检查并更新：

1. `apps/agent/swift/Sources/CicadaCore/Models.swift`
2. `apps/agent/swift/Sources/CicadaSystem/MacOSCommandGateway.swift`
3. 必要时更新 `apps/agent/swift/Sources/CicadaRelayClient/RelayDaemonService.swift`

然后运行：

```bash
cd /path/to/Cicada
pnpm run lint:agent
pnpm run test:agent
pnpm run build:agent
```

## 一致性检查

```bash
cd /path/to/Cicada
rg -n "apps/relay/packages/shared|apps/agent/packages/shared" . --glob "*.md"
```

目标：不再出现已删除路径的可执行指令。

## 相关文档

1. [命令清单](./COMMANDS.md)
2. [命令验证架构](../../../docs/architecture/command-validation.md)
3. [命令验证最佳实践](../../../docs/best-practices/validation.md)
4. [CicadaRelay README](../../apps/relay/README.md)
