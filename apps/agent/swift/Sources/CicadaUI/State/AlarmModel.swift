import Foundation

/// 警戒触发状态 + `AlarmEngineDelegate` 协议（供 Xcode 宿主注入）。
///
/// 警戒触发流程（同进程桥接，v1 C-7 决策）：
/// 1. `SentryMonitorRuntime.onAlarm(reason)` → `Sentry.triggerAlarm(reason:)` → `onAlarmingActivaty(reason)` 闭包
/// 2. Xcode 宿主在创建 Sentry 时注入闭包：`onAlarmingActivaty: { reason in appModel.alarm.activate(reason: reason) }`
/// 3. `ControlCenterRoot` 或 App 观察 `alarm.isActive`，`true` 时 `openWindow("alarm")`
/// 4. AlarmOverlay 停止按钮 → `appModel.alarm.stop()` → `delegate?.alarmDidStop()` → 宿主 controller.stop()
@MainActor
public final class AlarmModel: ObservableObject {
    @Published public private(set) var isActive: Bool = false
    @Published public private(set) var reason: String = ""

    /// 弱引用 delegate，避免循环。Xcode 宿主的 controller 实现此协议。
    public weak var delegate: AlarmEngineDelegate?

    /// 触发警戒。
    public func activate(reason: String) {
        isActive = true
        self.reason = reason
    }

    /// 同步清理告警展示状态，不触发引擎 delegate。
    public func reset() {
        isActive = false
        reason = ""
    }

    /// 停止警戒。实际停止动作由 Xcode 宿主 controller 执行（通过 delegate 回调）。
    public func stop() async {
        reset()
        await delegate?.alarmDidStop()
    }
}

/// 警戒引擎委托协议，供 Xcode 宿主的 controller 实现。
///
/// - `alarmDidStop()`：调宿主 controller 的停止入口
/// - 触发时 sentry.onAlarmingActivaty 回调调 `appModel.alarm.activate(reason:)`
public protocol AlarmEngineDelegate: AnyObject {
    func alarmDidStop() async
}
