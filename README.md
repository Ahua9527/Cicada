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

需要 Bun（版本见 `package.json` 的 `packageManager`）。除部署工具 Wrangler 外都不需要 Node；真部署前请装好 Node 24（Cloudflare 官方只支持在 Node 上运行 Wrangler）。
脚本一律用 `bun run <脚本名>`：直接敲 `bun test`、`bun build` 会调用 Bun 自带的测试器和打包器，绕过这里的脚本和配置。

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
