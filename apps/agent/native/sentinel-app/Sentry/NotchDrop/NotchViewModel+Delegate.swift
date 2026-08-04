//
//  NotchViewModel+Delegate.swift
//  Sentry
//
//  P4 宿主接入：NotchViewModel conform NotchDropDelegate，复用宿主既有引擎
//  （TrayDrop / AirDrop / interfaceConvert / NSWorkspace / notchClose / 外链）。
//

import CicadaUI
import Cocoa
import Foundation

extension NotchViewModel: NotchDropDelegate {
    // MARK: - TrayDrop 暂存引擎

    func loadTray(providers: [NSItemProvider]) {
        // interfaceConvert() 内部用 DispatchSemaphore 同步阻塞，落盘走后台线程。
        DispatchQueue.global().async { TrayDrop.shared.load(providers) }
    }

    func clearTray() {
        TrayDrop.shared.removeAll()
        notchClose()
    }

    // MARK: - AirDrop 引擎

    func airDrop(providers: [NSItemProvider]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.notchClose() }
        // interfaceConvert() 用 DispatchSemaphore 同步阻塞，禁止主线程调用（会卡 UI）。
        DispatchQueue.global().async {
            guard let urls = providers.interfaceConvert() else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AirDrop(files: urls).begin()
            }
        }
    }

    func airDrop(urls: [URL]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.notchClose() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            AirDrop(files: urls).begin()
        }
    }

    func openTrayPicker() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.notchClose() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let picker = NSOpenPanel()
            picker.allowsMultipleSelection = true
            picker.canChooseDirectories = true
            picker.canChooseFiles = true
            picker.begin { response in
                if response == .OK {
                    AirDrop(files: picker.urls).begin()
                }
            }
        }
    }

    // MARK: - 面板控制

    func close() {
        notchClose()
    }

    // showSettings() 已在 NotchViewModel 自身实现（路由到控制中心设置 Tab），
    // 签名与 NotchDropDelegate 协议一致，自动满足协议要求，此处不重复声明，
    // 否则报 invalid redeclaration。

    // MARK: - 外链

    func openGitHub() {
        NSWorkspace.shared.open(productPage)
        notchClose()
    }

    func openSponsor() {
        NSWorkspace.shared.open(sponsorPage)
        notchClose()
    }
}