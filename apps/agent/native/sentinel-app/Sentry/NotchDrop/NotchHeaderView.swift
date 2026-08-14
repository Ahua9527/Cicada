//
//  NotchHeaderView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import ColorfulX
import SwiftUI

struct NotchHeaderView: View {
    @StateObject var vm: NotchViewModel
    /// ⋯ 返回钮悬停态:放大热区后的 hover 反馈。
    @State private var backHover = false

    var body: some View {
        HStack {
            Text(String(localized: "NotchDrop"))
            .contentTransition(.numericText())
            Spacer()
            // 热区扩到 28×28(原热区只有省略号字形本身,太难点中)。
            Button(action: vm.dismissNotification) {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
                    .background(backHover ? Color.white.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { backHover = $0 }
            .animation(.easeOut(duration: 0.1), value: backHover)
            .accessibilityLabel(NSLocalizedString("Back to tray", comment: ""))
        }
        .animation(vm.animation, value: vm.contentType)
        .font(.system(.headline, design: .rounded))
    }
}

#Preview {
    NotchHeaderView(vm: .init())
}
