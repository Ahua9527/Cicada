//
//  NotchContentView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//  P4 重构：内容路由换用 CicadaUI 的 NotchPanel / NotchMenu（.notification 保留宿主视图）。
//

import CicadaUI
import ColorfulX
import SwiftUI
import UniformTypeIdentifiers

struct NotchContentView: View {
    @StateObject var vm: NotchViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch vm.contentType {
            case .normal:
                // 注入既有 TrayView 作为暂存区：它观察 TrayDrop.shared，覆盖空态拖放区
                // 与已暂存文件的打开/拖拽/删除列表。包内 NotchSection(.tray) 只剩空态，会
                // 让拖入的文件无法取回/管理。
                NotchPanel(delegate: vm, onShowMenu: vm.showMenu)
                    .environment(\.trayContent) { AnyView(TrayView(vm: vm)) }
                    .transition(contentTransition)
            case .menu:
                NotchMenu(delegate: vm)
                    .transition(contentTransition)
            case .notification:
                if let payload = vm.notificationPayload {
                    NotchDropNotificationView(payload: payload, vm: vm)
                        .transition(contentTransition)
                }
            }
        }
        // P2-1:reduceMotion 时退化为纯淡入,不做缩放位移。
        .animation(reduceMotion ? .easeOut(duration: 0.2) : vm.animation, value: vm.contentType)
    }

    private var contentTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity)
    }
}

#Preview {
    NotchContentView(vm: .init())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.black)
        .preferredColorScheme(.dark)
}
