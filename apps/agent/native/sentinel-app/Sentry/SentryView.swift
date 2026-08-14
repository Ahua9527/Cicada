//
//  SentryView.swift
//  Sentry
//
//  Created by 秋星桥 on 5/24/25.
//  P4 重构：用 CicadaUI 的 AlarmOverlayContent 组合，替换旧 texts/eye。
//

import CicadaUI
import ColorfulX
import SwiftUI

struct SentryView: View {
    @StateObject var sentry: Sentry
    // P4：警戒窗口由 SkyLightOperator 创建在 SwiftUI Scene 之外，@EnvironmentObject 不可达，
    // 故通过参数直传 AppModel.shared（由 Sentry.makeDefaultWindowController 注入）。
    @ObservedObject var appModel: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            if sentry.isAlrming {
                ColorfulView(
                    color: .sunset,
                    speed: .constant(reduceMotion ? 0 : 1),
                    noise: .constant(64)
                )
                    .transition(.opacity)
                    .ignoresSafeArea()
                Rectangle().fill(.ultraThinMaterial).opacity(0.5)
                AlarmOverlayContent(reason: appModel.alarm.reason) {
                    // 停止链路：AlarmModel.stop() → controller.stop() → finishCurrentSession()。
                    Task { await appModel.alarm.stop() }
                }
            } else {
                // 非告警态：仅展示已激活监控占位，不暴露「停止警戒」（避免误中断监控）。
                MonitoringOverlayContent()
            }
        }
        .frame(width: 700, height: 400, alignment: .center)
        .foregroundStyle(sentry.isAlrming ? .white : .primary)
        .animation(.interactiveSpring(), value: sentry.isAlrming)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 入场:Design.md §10 既定方案——spring(response: 0.4) + 轻微 scale + 淡入。
        // 下一 runloop 启动(等 SkyLight 窗口上屏),替代原 0.25s 空等 + 1s easeInOut;
        // 警报音与画面同帧到达。reduceMotion 退化为 0.2s 纯淡入。
        .opacity(appeared ? 1 : 0)
        .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.96))
        .onAppear {
            DispatchQueue.main.async {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4)) {
                    appeared = true
                }
            }
        }
    }
}

#Preview {
    let s = Sentry(configuration: .init(), onAlarmingActivaty: { _ in })
    SentryView(sentry: s, appModel: AppModel())
        .onAppear { s.isAlrming = true }
        .frame(width: 700, height: 400)
}
