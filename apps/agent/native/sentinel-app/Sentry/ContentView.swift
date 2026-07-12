//
//  ContentView.swift
//  Sentry
//
//  Created by 秋星桥 on 5/24/25.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var vm: ViewModel = .shared
    @StateObject private var controller: SentinelController = .shared

    private func configureTimerCallback() {
        vm.setTimerCallback {
            controller.handleTimerTick()
        }
    }

    var body: some View {
        SentryControlCenterView()
        .onAppear {
            configureTimerCallback()
        }
    }
}

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

private struct ContentViewPreviewContainer: View {
    @StateObject private var appDelegate = AppDelegate()

    var body: some View {
        ContentView()
            .environmentObject(appDelegate)
    }
}

#Preview {
    ContentViewPreviewContainer()
}
