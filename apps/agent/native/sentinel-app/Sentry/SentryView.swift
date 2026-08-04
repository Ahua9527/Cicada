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

    @State private var globalOpacity: Double = 0

    var body: some View {
        ZStack {
            if sentry.isAlrming {
                ColorfulView(color: .sunset, noise: .constant(64))
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
        .opacity(globalOpacity)
        .animation(.easeInOut(duration: 1), value: globalOpacity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                globalOpacity = 1
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
