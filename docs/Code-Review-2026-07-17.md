# Cicada 全量 AI Code Review 报告

**日期**：2026-07-17
**范围**：apps/agent/swift（CicadaUI library）、apps/agent/native/sentinel-app/Sentry（Xcode 宿主）、apps/relay + packages/shared（TS Worker）
**方式**：3 个 code-reviewer agent 并行审查，团队汇总

---

## 0. 总览

| 模块 | 文件量 | 健康度 | Critical | High | Medium | Low |
|------|--------|--------|----------|------|--------|-----|
| CicadaUI (SwiftPM) | ~54 .swift | 良好 | 1 | 4 | 6 | 4 |
| Sentry 宿主 (Xcode) | ~28 .swift | 良 | 0 | 3 | 5 | 5 |
| Relay + shared (TS) | ~70 .ts | 中 | 1 | 4 | 7 | 5 |

三块架构都清晰，P4.2 接入层设计正确、无死代码残留。主要风险集中在：**Bark 推送 URL 注入**（两模块各一份）、**并发安全**（Swift IPC client / Socket server）、**Relay 安全裸奔面**（设备信息未授权 + 速率限制可绕过）、**规格与实现脱节**（D1/Cron 未实现）。

---

## 1. Critical（必须修）

### C1. Bark 推送 URL 路径注入 — Swift 两处
- **CicadaUI** `Net/BarkClient.swift:27-29`：`endpoint.appendingPathComponent(title).appendingPathComponent(body)` 未 percent-encode，中文/空格/斜杠破坏 URL 或注入额外路径段。
- **Sentry 宿主** `Sentry.swift:216-236`：`makeBarkRequest` 同样把报警原因直接塞进 URL path；icon 仍指向旧品牌 `github.com/Lakr233/Sentry`。
- **修复**：统一改用 `URLComponents`，title/body 入 query 或 POST JSON body，path 段 `addingPercentEncoding`；icon 换 Cicada 资源。两处应共用一套实现（当前 CicadaUI 和宿主各有一份，本身也是重复）。
- **测试**：BarkClient 当前零测试，修复时补 URL 构造 + 错误路径单测。

### C2. Relay 规格与实现严重背离 — D1/Cron 未实现
- `wrangler.toml` 无 D1 binding、`Env` 无 `D1Database`、全仓无 `prepare()/bind()`；`index.ts` 仅导出 `fetch`，无 `scheduled`，无 `[triggers]/crons`。
- 设备注册表实际存于 Durable Object storage + 内存 Map，离线检测依赖 DO 内 `setInterval`，DO 被驱逐后定时器停止，`connected:true` 记录可能永久残留。
- **修复**：用 `state.storage.setAlarm()` 做离线巡检与注册表 GC，或补齐 Cron + D1 方案；明确择一并更新 wrangler/Env/规格文档。SQL 注入面因此不存在（无 SQL），但可靠性缺口必须补。

---

## 2. High

### Swift — CicadaUI

**H1. IPC async wrapper data race** — `IPC/SentinelControl+Async.swift` + `SleepHoldControl+Async.swift`
`Task.detached { try self.status() }` 把含可变 POSIX socket 状态的 client 逃逸到 detached 任务，多 model 在 3s 轮询中并发调用存在真实 data race。Swift 5.9 未报错但隐患真实。修复：client 标 `Sendable`/改 `actor`/每次调用创建短期 client。

**H2. SentinelsModel.refresh 陈旧状态** — `State/SentinelsModel.swift:24-32`
snap 为 nil 时 `lastSnapshot`/`readiness`/`activeTriggerCount` 保留上一轮值，UI 与实际不一致。修复：nil 时清空这三项。

**H3. NotchSection.onDrop 无条件 return true** — `Views/NotchDrop/NotchSection.swift:37-40`
`.data` 通配 UTI + 不校验 providers 即返回成功。修复：收窄 UTI，delegate 返回 bool 后再决定。

**H4. MenuBarDropdown onAppear 重复 refresh 无取消** — `Views/MenuBar/MenuBarDropdown.swift:47`
菜单快速开关叠 IPC 请求。修复：持有 Task 句柄 `.onDisappear` cancel。

### Swift — Sentry 宿主

**H5. appDataDirectoryURL 实现错误** — `MaintenanceHostInjections.swift:88-92`
注释写「与 openSavedClips 同根」，实际返回容器 `Application Support`，而录像在 `Documents/VideoClip`，按钮误导用户。修复：改 `videoClipDir.deletingLastPathComponent()`，统一路径来源到 helper。

**H6. IPC/Notifier Server fd/running 跨线程无同步** — `SentinelIPC.swift:66-84`、`SentinelNotifierServer.swift:121-139`
`start/stop` 主线程写、`acceptLoop` 专用 queue 读，无锁无 atomic。修复：`os_unfair_lock` 保护，`stop` 用 `shutdown(fd, SHUT_RDWR)` 唤醒阻塞 accept。

### TS — Relay

**H7. 速率限制可绕过** — `rate-limit.middleware.ts`
模块级 `Map` 多 isolate 不共享；`x-forwarded-for` 可伪造；`context.deviceId` 全链路从未赋值始终退化 IP。修复：DO/KV 分布式计数，优先 `cf-connecting-ip`。

**H8. 设备信息未授权泄露** — `/devices`、`/status`、`/health` 无鉴权
`handleRegistryDevices` 返回 `ipAddress`/`userAgent`/在线状态给任意请求者。修复：加管理端鉴权，默认屏蔽 IP/User-Agent。

**H9. 每条 WS 消息全量持久化** — `handleIncomingMessage`
每个 ping/pong 都 `waitUntil(saveSessions())` 写回全部 sessions + nonces，高频心跳耗尽 DO storage 写配额。修复：节流写（≥30s 或累积 N 次变更）。

**H10. NonceValidator.cleanup 误删** — `shared/nonce.validator.ts:29`
超阈值时 `clear()` 清空全部，等于一次性放行所有历史 nonce 重放。修复：按时间淘汰而非整体清空。

---

## 3. Medium（精选）

### CicadaUI
- **M1** ConfigModel 主线程同步落盘（`ConfigModel.swift:10-15`）—— Toggle 点击阻塞主线程，改 async/防抖。
- **M2** SnapshotMapper 重复硬编码 dangerStates 字符串（`SnapshotMapper.swift:11,60`）—— 抽 `static let`。
- **M3** activeTriggerCount 魔法数 3（`SentinelsModel.swift:31`）—— 从 SentryConfiguration 计算启用数。
- **M4** AppModel 轮询无错误退避（`AppModel.swift:48-54`）—— 加指数退避或最大周期保护。

### Sentry 宿主
- **M5** `Sentry.swift:393` `.main!` 强解包——头less/远程会话崩溃，改 guard let。
- **M6** `openMainWindow` 遍历所有窗口置前（`SentinelController.swift:130-132`）—— 会拉起 MenuBarExtra/NotchDrop，按 identifier 过滤。
- **M7** `Security.removeDebugger` dlopen 校验不可靠（`Security.swift:55`）—— Apple Silicon 合法指针可能 ≤0x1024，反调试失效，改 `dlsym` 可选解包。
- **M8** `struct App` 与 `SwiftUI.App` 同名（`App.swift:11`）—— 改名 `CicadaApp`。

### Relay
- **M9** shortcut tokenHash 非恒定时间比较（`handleShortcutCommand`）—— 时序侧信道，改恒定时间。
- **M10** relay 边界未复用 shared deviceId/sessionId 校验（`session.controller.ts:76`）—— 直接转发原值。
- **M11** 请求体限制可绕过（`requestSizeLimitMiddleware`）—— 仅校验 content-length，chunked 跳过。
- **M12** CORS 默认放行任意源（`allowedOrigins.length===0` 时）。
- **M13** 错误码不一致——DO 内字面量与 shared `ErrorCode` 枚举未对齐。

---

## 4. Low（略，详见各模块分报告）

要点：Security.secCall 指针泄漏、Sentry.startRecording 非 weak self、NotchDropDelegatePreviewMock 计数器非线程安全、relay `setInterval.unref()` Node API 在 Worker 无效、`dist/` 进仓库。

---

## 5. 可立即采纳的高 ROI 修复（按优先级）

| # | 问题 | 工作量 | 影响 |
|---|------|--------|------|
| 1 | C1 BarkClient URL 注入（两处统一改 URLComponents） | ~20 行 | 消掉注入面 + 去重 |
| 2 | H8 /devices /status 加鉴权 | ~30 行 | 堵信息泄露 |
| 3 | H2 SentinelsModel nil-snap 清空 | 3 行 | 修 UI 状态不一致 |
| 4 | H10 NonceValidator 按时间淘汰 | ~10 行 | 堵重放窗口 |
| 5 | M2+M3 SnapshotMapper 抽 dangerStates + 计算 triggerCount | ~15 行 | 去重+解耦 |
| 6 | M5 `.main!` 改 guard let | 2 行 | 防崩溃 |
| 7 | M7 removeDebugger 改 dlsym | ~5 行 | 修反调试失效 |
| 8 | M8 App→CicadaApp 改名 | 1 行 | 消名冲突隐患 |
| 9 | H5 appDataDirectoryURL 路径修正 | 5 行 | 修按钮误导 |
| 10 | H9 saveSessions 节流 | ~15 行 | 降 DO 写配额消耗 |

C2（D1/Cron 规格背离）属于架构决策，需华哥定方向后再排期。

---

## 6. 不建议改动

- **CicadaUI**：AlarmEye Canvas 构图常量（锁定 Design.md §5.2）、DesignMetrics/Color+Cicada 设计令牌、HostInjections EnvironmentKey 注入模式、NotchDropDelegate 8 方法协议形态、PublicAPITests 无 @testable 约束。
- **Sentry 宿主**：P4.2 接入层 ControlCenterRouter+Host / MaintenanceHostInjections 的 Task {@MainActor} 派发模式、ViewModel 1s 定时器状态机。
- **Relay**：shortcut 路径的 Bearer token + grant + 命令白名单设计、Ed25519 注册签名 + nonce 防重放、sanitizeError 脱敏层。

---

## 7. 测试覆盖缺口

- **CicadaUI**：BarkClient 零测试、ConfigModel.saveConnection 状态机未覆盖、AppModel 轮询生命周期无测试、SnapshotMapper.toDiagnostic running 态未测、Notch 拖放转发无测试。
- **Sentry 宿主**：引擎层（相机/报警/NotchDrop）无单测，依赖运行时验证。
- **Relay**：安全测试分区存在但未覆盖 H7/H8（速率限制绕过/设备信息泄露）；DO Alarm 离线巡检无测试（因未实现）。

---

*本报告由 3 个 code-reviewer agent 并行审查汇总，未修改任何文件。*