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

    var body: some View {
        ZStack {
            switch vm.contentType {
            case .normal:
                NotchPanel(delegate: vm)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            case .menu:
                NotchMenu(delegate: vm)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            case .notification:
                if let payload = vm.notificationPayload {
                    NotchDropNotificationView(payload: payload, vm: vm)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
        }
        .animation(vm.animation, value: vm.contentType)
    }
}

#Preview {
    NotchContentView(vm: .init())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.black)
        .preferredColorScheme(.dark)
}