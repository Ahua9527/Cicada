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

    private var showsSavedClips: Bool {
        controller.showsSavedClips
    }

    private func openSavedClips() {
        controller.openSavedClips()
    }

    @ViewBuilder
    private var completionActions: some View {
        if showsSavedClips {
            Button("Open Saved Clips", action: openSavedClips)
        }
        Button("Exit") {
            NSApp.terminate(nil)
        }
    }

    var body: some View {
        ZStack {
            switch vm.status {
            case .welcome:
                WelcomePanel()
            case .running:
                VStack(spacing: 32) {
                    EyeView()
                }
                .padding(64)
            case .activityDetected:
                VStack(spacing: 16) {
                    Image(systemName: "light.beacon.max")
                        .font(.largeTitle)
                    Text("Activity Detected")
                        .bold()
                    Divider()
                    Text(controller.activityHint)
                    Divider()
                    HStack {
                        completionActions
                    }
                }
                .padding(64)
            case .completed:
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    Text("Sentry Completed")
                        .bold()
                    Divider()
                    HStack {
                        completionActions
                    }
                }
                .padding(64)
                .onAppear {
                    controller.sentry?.stop()
                }
            }
        }
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
