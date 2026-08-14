//
//  TrayDrop+DropItemView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/8.
//

import Foundation
import Pow
import SwiftUI
import UniformTypeIdentifiers

struct DropItemView: View {
    let item: TrayDrop.DropItem
    let index: Int
    let animateEntry: Bool
    @StateObject var vm: NotchViewModel
    @StateObject var tvm: TrayDrop

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    @State private var deleteHover = false
    @State private var hasEntered: Bool

    init(
        item: TrayDrop.DropItem,
        index: Int,
        animateEntry: Bool,
        vm: NotchViewModel,
        tvm: TrayDrop = .shared
    ) {
        self.item = item
        self.index = index
        self.animateEntry = animateEntry
        _vm = StateObject(wrappedValue: vm)
        _tvm = StateObject(wrappedValue: tvm)
        _hasEntered = State(initialValue: !animateEntry)
    }

    private var entryDelay: Double {
        0.05 * Double(min(index, 4))
    }

    /// P1-3:删除钮可见性——Option 全量揭示(加速器,保留),或悬停单项揭示
    /// (macOS 惯例的直接操作);deleteHover 让指针移到 × 本体上时不消失。
    private var deleteRevealed: Bool {
        vm.optionKeyPressed || hover || deleteHover
    }

    private var entryScale: CGFloat {
        reduceMotion || hasEntered ? 1 : 0.96
    }

    var body: some View {
        Button(action: openItem) {
            VStack {
                Image(nsImage: item.workspacePreviewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 64)
                Text(item.fileName)
                    .multilineTextAlignment(.center)
                    .font(.system(.footnote, design: .rounded))
                    .frame(maxWidth: 64)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .transition(.asymmetric(
            insertion: .identity,
            // P1-2:容器动画事务激活后 poof 才真正播放;reduceMotion 退化为纯淡出。
            removal: reduceMotion ? .opacity : .movingParts.poof
        ))
        .opacity(hasEntered ? 1 : 0)
        .scaleEffect(entryScale)
        .animation(.easeOut(duration: 0.2).delay(entryDelay), value: hasEntered)
        .onAppear {
            guard animateEntry else { return }
            hasEntered = true
            tvm.consumeEntryAnimation(for: item.id)
        }
        .onHover { hover = $0 }
        .scaleEffect(hover ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: hover)
        .onDrag { NSItemProvider(contentsOf: item.storageURL) ?? .init() }
        .accessibilityLabel(Text(item.fileName))
        .accessibilityHint(Text(NSLocalizedString("Open file", comment: "")))
        .accessibilityAction(named: Text(NSLocalizedString("Delete stored file", comment: ""))) {
            tvm.delete(item.id)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                tvm.delete(item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.red)
                    .background(Color.white.clipShape(Circle()).padding(1))
                    .frame(width: vm.spacing, height: vm.spacing)
            }
            .buttonStyle(.plain)
            .opacity(deleteRevealed ? 1 : 0)
            .allowsHitTesting(deleteRevealed)
            .onHover { deleteHover = $0 }
            .animation(.easeOut(duration: 0.1), value: deleteRevealed)
            .accessibilityHidden(true)
            .offset(x: vm.spacing / 2, y: -vm.spacing / 2)
        }
    }

    private func openItem() {
        guard !vm.optionKeyPressed else { return }
        vm.notchClose()
        DispatchQueue.main.async {
            NSWorkspace.shared.open(item.storageURL)
        }
    }
}
