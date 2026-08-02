//
//  ViewModel.swift
//  Sentry
//
//  P4.2：原 ContentView.swift 精简为 ViewModel.swift。
//  ContentView 结构体已删除（被 CicadaUI 的 ControlCenterRoot 替换），
//  保留 ViewModel 类（SentinelController / 1s 定时器状态机深度依赖 ViewModel.shared）。
//

import AppKit
import Foundation

/// 1s 定时器状态机：驱动 welcome → running → activityDetected → completed。
///
/// `SentinelController.shared` 通过 `setTimerCallback` 注册 `handleTimerTick`；
/// 该接线在 `AppDelegate.applicationDidFinishLaunching` 完成（P4.2 从旧
/// `ContentView.onAppear` 迁入），一次性接线、全程生效。
final class ViewModel: ObservableObject {
    static let shared = ViewModel()

    private init() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.callback()
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    enum PanelStatus {
        case welcome
        case running
        case activityDetected
        case completed
    }

    @Published var status: PanelStatus = .welcome

    private var callback = {}

    func setTimerCallback(_ cb: @escaping () -> Void) {
        callback = cb
    }
}