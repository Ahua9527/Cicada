//
//  TrayDrop+View.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/8.
//

import SwiftUI

struct TrayView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var tvm = TrayDrop.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var targeting = false

    var storageTime: String {
        switch tvm.selectedFileStorageTime {
        case .oneHour:
            return NSLocalizedString("an hour", comment: "")
        case .oneDay:
            return NSLocalizedString("a day", comment: "")
        case .twoDays:
            return NSLocalizedString("two days", comment: "")
        case .threeDays:
            return NSLocalizedString("three days", comment: "")
        case .oneWeek:
            return NSLocalizedString("a week", comment: "")
        case .never:
            return NSLocalizedString("forever", comment: "")
        case .custom:
            let localizedTimeUnit = NSLocalizedString(tvm.customStorageTimeUnit.localized.lowercased(), comment: "")
            return "\(tvm.customStorageTime) \(localizedTimeUnit)"
        }
    }

    var body: some View {
        panel
            .onDrop(of: [.data], isTargeted: $targeting) { providers in
                DispatchQueue.global().async { tvm.load(providers) }
                return true
            }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: vm.cornerRadius)
            .strokeBorder(style: StrokeStyle(lineWidth: 4, dash: [10]))
            .foregroundStyle(targeting ? Color.blue.opacity(0.8) : Color.white.opacity(0.1))
            .background(loading)
            .overlay {
                content
                    .padding()
            }
            .animation(vm.animation, value: tvm.isLoading)
            .animation(.easeOut(duration: 0.12), value: targeting)
    }

    var loading: some View {
        RoundedRectangle(cornerRadius: vm.cornerRadius)
            .foregroundStyle(
                targeting
                    ? Color.blue.opacity(0.15)
                    : (reduceMotion && tvm.isLoading > 0 ? Color.blue.opacity(0.25) : Color.white.opacity(0.1))
            )
            .conditionalEffect(
                .repeat(
                    .glow(color: .blue, radius: 50),
                    every: 1.5
                ),
                condition: tvm.isLoading > 0 && !reduceMotion
            )
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")

                    Text(NSLocalizedString("Drag files here to keep them for", comment: "") + " " + storageTime + " " + NSLocalizedString("& Press Option to delete", comment: ""))
                        .font(.system(.headline, design: .rounded))
                }
                .foregroundStyle(targeting ? Color.blue : Color.white)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: vm.spacing) {
                        ForEach(Array(tvm.items.enumerated()), id: \.element.id) { index, item in
                            DropItemView(
                                item: item,
                                index: index,
                                animateEntry: tvm.entryAnimations.contains(item.id),
                                vm: vm,
                                tvm: tvm
                            )
                        }
                    }
                    .padding(vm.spacing)
                }
                .padding(-vm.spacing)
                .scrollIndicators(.never)
                // P1-2:items 变更进入动画事务——激活 DropItemView 声明的 poof 移除过渡,
                // 同时让兄弟项以同一 spring 让位/补位,重排不再瞬移。
                // 入场仍由 DropItemView 的手动 hasEntered 方案负责(独立事务,互不干扰)。
                .animation(reduceMotion ? .easeOut(duration: 0.2) : vm.animation, value: tvm.items)
            }
        }
    }
}

#Preview {
    NotchContentView(vm: .init())
        .padding()
        .frame(width: 550, height: 150, alignment: .center)
        .background(.black)
        .preferredColorScheme(.dark)
}
