import SwiftUI

private enum HoldToConfirmTiming {
    static let holdDuration = 2.0
    static let resetDuration = 0.2
}

/// 按住确认的最小状态机。与 SwiftUI 视图分离，保证取消或重复回调不能重复执行动作。
struct HoldConfirmationState {
    private(set) var isPressing = false
    private(set) var hasCompleted = false

    mutating func begin() {
        isPressing = true
        hasCompleted = false
    }

    mutating func cancel() {
        isPressing = false
    }

    mutating func complete() -> Bool {
        guard isPressing, !hasCompleted else { return false }
        hasCompleted = true
        return true
    }
}

/// 按住确认动作的文案组合（内部）：标题、说明、确认按钮、辅助功能标签与提示。
struct HoldConfirmationCopy {
    let title: String
    let message: String
    let confirmTitle: String
    let accessibilityLabel: String
    let accessibilityHint: String
}

extension HoldConfirmationCopy {
    /// 清空托盘（默认）：沿用既有文案。
    static let clearTray = HoldConfirmationCopy(
        title: String(localized: "清空 NotchDrop 托盘？", bundle: .module),
        message: String(
            localized: "此操作会永久删除托盘中的所有文件，且无法撤销。",
            bundle: .module
        ),
        confirmTitle: String(localized: "清空", bundle: .module),
        accessibilityLabel: String(localized: "清空 NotchDrop 托盘", bundle: .module),
        accessibilityHint: String(
            localized: "按住两秒可清空托盘。通过键盘或 VoiceOver 激活后，需在确认窗口中再次确认。",
            bundle: .module
        )
    )

    /// 退出 App：明确提示退出后远程控制和安防监控会停止，确认按钮为「退出」。
    static let quitApp = HoldConfirmationCopy(
        title: String(localized: "退出 Cicada？", bundle: .module),
        message: String(
            localized: "退出后远程控制和安防监控会停止。",
            bundle: .module
        ),
        confirmTitle: String(localized: "退出", bundle: .module),
        accessibilityLabel: String(localized: "退出 Cicada", bundle: .module),
        accessibilityHint: String(
            localized: "按住两秒可退出 Cicada。通过键盘或 VoiceOver 激活后，需在确认窗口中再次确认。",
            bundle: .module
        )
    )
}

/// 仅用于少量不可恢复动作的按住确认按钮。
///
/// 按住时用 2 秒线性进度填充，提前松开以 200ms 回退。减弱动态效果时保留透明度反馈，
/// 取消水平缩放，避免位置/缩放运动。
struct HoldToConfirmButton<Label: View>: View {
    private let tint: Color
    private let cornerRadius: CGFloat
    private let copy: HoldConfirmationCopy
    private let action: () -> Void
    private let label: Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmation = HoldConfirmationState()
    @State private var progress: CGFloat = 0
    @State private var showingAccessibilityConfirmation = false

    init(
        tint: Color,
        cornerRadius: CGFloat,
        copy: HoldConfirmationCopy = .clearTray,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.copy = copy
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button {
            showingAccessibilityConfirmation = true
        } label: {
            label
                .overlay {
                    Rectangle()
                        .fill(tint.opacity(0.32))
                        .scaleEffect(
                            x: reduceMotion ? 1 : progress,
                            y: 1,
                            anchor: .leading
                        )
                        .opacity(reduceMotion ? progress : 1)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copy.accessibilityLabel)
        .accessibilityHint(copy.accessibilityHint)
        .overlay {
            Color.clear
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
                .accessibilityHidden(true)
                .onLongPressGesture(
                    minimumDuration: HoldToConfirmTiming.holdDuration,
                    maximumDistance: 16,
                    perform: completeConfirmation,
                    onPressingChanged: updatePressing
                )
        }
        .alert(
            copy.title,
            isPresented: $showingAccessibilityConfirmation
        ) {
            Button(String(localized: "取消", bundle: .module), role: .cancel) {}
            Button(copy.confirmTitle, role: .destructive) {
                action()
            }
        } message: {
            Text(copy.message)
        }
    }

    private func updatePressing(_ isPressing: Bool) {
        if isPressing {
            confirmation.begin()
            withAnimation(.linear(duration: HoldToConfirmTiming.holdDuration)) {
                progress = 1
            }
        } else {
            confirmation.cancel()
            resetProgress()
        }
    }

    private func completeConfirmation() {
        guard confirmation.complete() else { return }
        action()
        resetProgress()
    }

    private func resetProgress() {
        // 松手回退是系统响应,用 ease-out 快速收敛(按压慢、松手快的非对称时序)。
        withAnimation(.easeOut(duration: HoldToConfirmTiming.resetDuration)) {
            progress = 0
        }
    }
}
