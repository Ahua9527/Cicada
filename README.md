# Cicada

Cicada 是一个 monorepo，包含 Cloudflare Relay、macOS Swift 后台 Agent，以及两端共享的协议契约包。

## 结构

```text
Cicada/
├── apps/
│   ├── relay/   # Cloudflare Worker + Durable Objects
│   └── agent/   # Swift CLI + LaunchAgent daemon + notifier
├── packages/
│   └── shared/  # TypeScript 协议、命令类型与验证规则
├── docs/
└── scripts/
```

## 开发命令

需要 Bun（版本见 `package.json` 的 `packageManager`）和 Node 24（Jest、Wrangler 仍运行在 Node 上）。
脚本一律用 `bun run <脚本名>`：`bun test`、`bun build` 是 Bun 自带的测试器和打包器，不是这里的脚本。

```bash
bun install

bun run build:relay
bun run lint:relay
bun run test:relay
bun run deploy:relay:dry-run

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bun run lint:agent
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bun run test:agent
bun run build:agent
```

统一命令：

```bash
bun run build
bun run lint
bun run test
```

## 包边界

- `apps/relay` 负责 Worker、Durable Object、Wrangler 配置和 Relay 测试。
- `apps/agent` 负责 Swift CLI、LaunchAgent daemon、notifier 与安装脚本。
- `packages/shared` 是命令契约唯一来源，Relay 通过 `@cicada/shared` workspace 依赖使用它。
- 本仓库只保留一个根 `.git`，不使用 submodule，也不继续维护双仓库发布链路。
