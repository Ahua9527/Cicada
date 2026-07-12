//
//  Sentry.swift
//  Sentry
//
//  Created by 秋星桥 on 5/24/25.
//

import AppKit
import AVFAudio
import AVFoundation
import AVKit
import Foundation
import SkyLightWindow
import SwiftUI

enum RecordingOutputURLBuilder {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return formatter
    }()

    static func makeURL(
        in directory: URL,
        now: Date = Date(),
        uuid: UUID = UUID()
    ) -> URL {
        let suffix = uuid.uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        let fileName = "Sentry_\(formatter.string(from: now))_\(suffix).mov"
        return directory.appendingPathComponent(fileName)
    }
}

@MainActor
final class Sentry: NSObject, ObservableObject {
    typealias WindowControllerFactory = (Sentry) -> NSWindowController?
    typealias WindowCloseAnimator = (NSView, @escaping () -> Void) -> Void
    typealias BarkRequestSender = (URLRequest) -> Void
    typealias RuntimeStopper = (SentryMonitorRuntime?, @escaping () -> Void) -> Void
    private typealias WindowCloseContext = (controller: NSWindowController, contentView: NSView?)

    @Published var isAlrming: Bool = false

    let configuration: SentryConfiguration
    let onAlarmingActivaty: (_ reason: String) -> Void

    enum Status {
        case idle
        case running
        case alarming
        case stopping
    }

    private var status: Status = .idle
    private var windowController: NSWindowController?
    private var runtime: SentryMonitorRuntime?
    private var runtimeStartTask: Task<Void, Never>?

    private var initialSpeakerVolume: Float = 0.0

    private var audioPlayer: AVAudioPlayer?
    private var volumeTimer: Timer?
    private var notificationPosted: Bool = false

    private let recordingController = CameraSessionController()
    private let shouldStartRuntimeLoop: Bool
    private let makeWindowController: WindowControllerFactory
    private let animateWindowClose: WindowCloseAnimator
    private let barkRequestSender: BarkRequestSender
    private let stopMonitorRuntime: RuntimeStopper
    private let readSystemVolume: () -> Float?
    private let setSystemVolume: (Float) -> Void

    var currentStatus: Status { status }
    var hasPostedNotification: Bool { notificationPosted }

    init(
        configuration: SentryConfiguration,
        onAlarmingActivaty: @escaping (_ reason: String) -> Void,
        shouldStartRuntimeLoop: Bool = true,
        makeWindowController: @escaping WindowControllerFactory = Sentry.makeDefaultWindowController,
        animateWindowClose: @escaping WindowCloseAnimator = Sentry.defaultWindowCloseAnimator,
        barkRequestSender: @escaping BarkRequestSender = Sentry.defaultBarkRequestSender,
        stopMonitorRuntime: @escaping RuntimeStopper = Sentry.defaultStopMonitorRuntime,
        readSystemVolume: @escaping () -> Float? = AlarmEngine.readSystemVolume,
        setSystemVolume: @escaping (Float) -> Void = AlarmEngine.setSystemVolume
    ) {
        self.configuration = configuration
        self.onAlarmingActivaty = onAlarmingActivaty
        self.shouldStartRuntimeLoop = shouldStartRuntimeLoop
        self.makeWindowController = makeWindowController
        self.animateWindowClose = animateWindowClose
        self.barkRequestSender = barkRequestSender
        self.stopMonitorRuntime = stopMonitorRuntime
        self.readSystemVolume = readSystemVolume
        self.setSystemVolume = setSystemVolume
        super.init()
    }

    func run() {
        guard status == .idle else { return }
        prepareForRun()
        startMonitorRuntimeIfNeeded()
    }

    func stop() {
        guard status != .idle, status != .stopping else { return }
        status = .stopping

        stopMonitorRuntime(detachRuntimeForStop()) { [weak self] in
            self?.finishStop()
        }
    }

    func unlockAlarm() {
        guard status == .alarming else { return }
        status = .running
        clearAlarmState()
        stopAlarm()

        let runtime = runtime
        Task {
            await runtime?.unlockAlarm()
        }
    }

    private func triggerAlarm(reason: String) {
        guard status == .running else { return }
        status = .alarming
        isAlrming = true
        notificationPosted = false
        onAlarmingActivaty(reason)
        executeAlarmActions(reason: reason)
    }

    private func executeAlarmActions(reason: String) {
        playAlarmSoundIfNeeded()
        sendAlarmNotificationIfNeeded(message: reason)
    }

    private func playAlarmSound() {
        guard let soundURL = Bundle.main.url(forResource: "alarm", withExtension: "mp3") else {
            assertionFailure()
            return
        }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            self.audioPlayer = audioPlayer
            audioPlayer.numberOfLoops = -1 // 无限循环
            audioPlayer.volume = 0.1 // 开始时 10% 音量
            audioPlayer.currentDevice = "BuiltInSpeakerDevice"
            audioPlayer.play()

            startVolumeTimer()
        } catch {
            print("[-] failed to play alarm sound: \(error)")
        }
    }

    private func startVolumeTimer() {
        volumeTimer?.invalidate()
        var currentStep = 0
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.status == .alarming else {
                    timer.invalidate()
                    return
                }
                AlarmEngine.setSystemVolume(1)

                currentStep += 1
                if currentStep <= 3 { return }

                let newVolume = min(1.0, 0.1 + Float(currentStep - 3) * 0.2)
                self.audioPlayer?.volume = newVolume

                print("[*] alarm sound volume: \(newVolume)")

                if newVolume >= 1.0 {
                    timer.invalidate()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        volumeTimer = timer
    }

    private func stopAlarm() {
        volumeTimer?.invalidate()
        volumeTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func playAlarmSoundIfNeeded() {
        guard configuration.sentryAlarmsSoundsEnabled else { return }
        playAlarmSound()
    }

    func sendBarkNotification(message: String) {
        guard !notificationPosted else { return }
        guard configuration.sentryAlarmsNotificationType == .bark else { return }
        guard let request = makeBarkRequest(message: message) else { return }
        notificationPosted = true
        barkRequestSender(request)
    }

    private func sendAlarmNotificationIfNeeded(message: String) {
        guard configuration.sentryAlarmsNotificationType == .bark else { return }
        sendBarkNotification(message: message)
    }

    private func makeBarkRequest(message: String) -> URLRequest? {
        guard let initialURL = URL(string: configuration.sentryNotificationConfigBark.endpoint) else {
            return nil
        }
        let newURL = initialURL
            .appendingPathComponent(String(localized: "Cicada - Mac"))
            .appendingPathComponent(message)
        guard var comps = URLComponents(url: newURL, resolvingAgainstBaseURL: false) else { return nil }
        comps.queryItems = [
            .init(name: "level", value: "critical"),
            .init(name: "volume", value: "5"),
            .init(name: "group", value: String(localized: "Cicada - Mac")),
            .init(name: "isArchive", value: "1"),
            .init(name: "call", value: "1"),
            .init(name: "icon", value: "https://github.com/Lakr233/Sentry/blob/main/Sentry/Assets.xcassets/icon-512.imageset/icon-512@2x.png?raw=true"),
        ]
        guard let url = comps.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return request
    }

    private func startRecording() {
        print("[*] start recording camera...")

        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            print("[*] camera permission not granted")
            return
        }
        let outputURL = makeRecordingOutputURL()

        recordingController.startRecording(
            deviceID: configuration.sentryRecordingDevice,
            outputURL: outputURL
        ) { outputURL, error in
            self.logRecordingCompletion(outputURL: outputURL, error: error)
        }

        print("[*] recording started to: \(outputURL.path)")
    }

    private func stopRecording() {
        print("[*] stop recording camera...")
        recordingController.stop()
    }

    private func finishStop() {
        let windowContext = detachWindowForClosing()
        restoreIdleState()
        closeWindowIfNeeded(windowContext)
    }

    private func prepareForRun() {
        status = .running
        clearAlarmState()
        windowController = makeWindowController(self)
        if configuration.sentryRecordingEnabled {
            startRecording()
        }
        initialSpeakerVolume = readSystemVolume() ?? 0
    }

    private func startMonitorRuntimeIfNeeded() {
        guard shouldStartRuntimeLoop else { return }
        let runtime = makeMonitorRuntime()
        self.runtime = runtime
        runtimeStartTask = Task {
            guard !Task.isCancelled else { return }
            await runtime.start()
        }
    }

    private func makeMonitorRuntime() -> SentryMonitorRuntime {
        SentryMonitorRuntime(
            configuration: configuration,
            onHeartbeat: {
                await MainActor.run {
                    SentryConfigurationManager.shared.communicateWithSleepHoldServiceIfNeeded()
                }
            },
            onAlarm: { [weak self] reason in
                await MainActor.run {
                    self?.triggerAlarm(reason: reason)
                }
            }
        )
    }

    private static func defaultStopMonitorRuntime(_ runtime: SentryMonitorRuntime?, completion: @escaping () -> Void) {
        guard let runtime else {
            completion()
            return
        }

        Task {
            await runtime.stop()
            await MainActor.run {
                completion()
            }
        }
    }

    private func detachRuntimeForStop() -> SentryMonitorRuntime? {
        runtimeStartTask?.cancel()
        runtimeStartTask = nil
        let currentRuntime = runtime
        runtime = nil
        return currentRuntime
    }

    private func restoreIdleState() {
        stopActiveOutputs()
        disconnectFromSleepHold()
        restoreInitialSpeakerVolume()
        clearAlarmState()
        status = .idle
    }

    private func stopActiveOutputs() {
        stopAlarm()
        stopRecording()
    }

    private func disconnectFromSleepHold() {
        SentryConfigurationManager.shared.disconnectFromSleepHold()
    }

    private func restoreInitialSpeakerVolume() {
        setSystemVolume(initialSpeakerVolume)
    }

    private func detachWindowForClosing() -> WindowCloseContext? {
        guard let currentWindowController = windowController else { return nil }
        let contentView = currentWindowController.window?.contentView
        windowController = nil
        return (currentWindowController, contentView)
    }

    private func closeWindowIfNeeded(_ context: WindowCloseContext?) {
        guard let context else { return }
        guard let contentView = context.contentView else {
            context.controller.close()
            return
        }

        animateWindowClose(contentView) {
            context.controller.close()
        }
    }

    private func clearAlarmState() {
        notificationPosted = false
        isAlrming = false
    }

    private func makeRecordingOutputURL() -> URL {
        try? FileManager.default.createDirectory(
            at: videoClipDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return RecordingOutputURLBuilder.makeURL(in: videoClipDir)
    }

    private func logRecordingCompletion(outputURL: URL, error: Error?) {
        if let error {
            print("[*] recording finished with error: \(error)")
        } else {
            print("[*] recording finished successfully: \(outputURL.path)")
        }
    }

    nonisolated private static func makeDefaultWindowController(for sentry: Sentry) -> NSWindowController? {
        SkyLightOperator.shared.delegateView(
            AnyView(SentryView(sentry: sentry)),
            toScreen: .main!
        )
    }

    nonisolated private static func defaultWindowCloseAnimator(_ contentView: NSView, _ completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            contentView.animator().alphaValue = 0
        } completionHandler: {
            completion()
        }
    }

    nonisolated private static func defaultBarkRequestSender(_ request: URLRequest) {
        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error {
                print("[*] bark push error: \(error)")
            }
        }.resume()
    }
}
