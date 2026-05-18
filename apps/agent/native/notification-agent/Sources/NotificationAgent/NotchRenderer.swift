import AppKit
import CoreGraphics
import Darwin
import Foundation
import NotchNotification
import SwiftUI

private struct NotchPayload {
    let level: NotificationLevel
    let title: String
    let message: String?
    let durationMs: Int
}

private struct NotchBodyView: View {
    let level: NotificationLevel
    let title: String
    let message: String?
    let theme: NotificationTheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.bodyVerticalSpacing) {
            Text(title)
                .font(theme.titleFont)
                .foregroundStyle(theme.titleColor)
                .lineLimit(1)
                .truncationMode(.tail)

            if let message, !message.isEmpty {
                Text(message)
                    .font(theme.messageFont)
                    .foregroundStyle(theme.messageColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(minWidth: theme.bodyMinWidth, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(level.accent.opacity(0.30), lineWidth: 0.9)
                )
        )
    }
}

private struct WindowState {
    let level: NSWindow.Level
    let collectionBehavior: NSWindow.CollectionBehavior
}

private enum RenderPhase {
    case idle
    case showing
    case closing
}

private struct ActiveWindowRef {
    let id: ObjectIdentifier
}

final class NotchRenderer {
    private let theme: NotificationTheme
    private let overlayWindowLevel: NSWindow.Level = {
        let shielding = CGShieldingWindowLevel()
        let cursor = CGWindowLevelForKey(.cursorWindow)
        let target = min(shielding + 1, cursor - 1)
        return NSWindow.Level(rawValue: Int(target))
    }()
    private let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
        .fullScreenAuxiliary,
        .canJoinAllSpaces,
        .stationary,
        .ignoresCycle,
    ]

    private let maxQueueSize = 100
    private let closeAnimationDurationMs = 200
    private let bindRetryDelayMs = 25
    private let maxBindRetryCount = 10
    private let overlayReapplyDelayMs = 110

    private var phase: RenderPhase = .idle
    private var displayToken: UInt64 = 0
    private var activeWindow: ActiveWindowRef?
    private var pendingQueue: [NotchPayload] = []
    private var closeRequestedWhileBinding = false
    private var originalWindowStates: [ObjectIdentifier: WindowState] = [:]
    private var windowCloseObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    init(theme: NotificationTheme = .default) {
        self.theme = theme
    }

    func render(level: String, title: String, message: String?, durationMs: Int) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.render(level: level, title: title, message: message, durationMs: durationMs)
            }
            return
        }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }

        let normalizedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = NotchPayload(
            level: NotificationLevel.from(rawValue: level),
            title: normalizedTitle,
            message: normalizedMessage,
            durationMs: max(durationMs, 500)
        )

        switch phase {
        case .idle:
            presentAsActive(payload)
        case .showing:
            enqueue(payload)
            startClosingActiveWindowIfNeeded()
        case .closing:
            enqueue(payload)
        }
    }

    private func present(payload: NotchPayload) {
        NotchNotification.present(
            leadingView: EmptyView(),
            trailingView: EmptyView(),
            bodyView: NotchBodyView(
                level: payload.level,
                title: payload.title,
                message: payload.message,
                theme: theme
            ),
            interval: Double(payload.durationMs) / 1000,
            animated: true
        )
    }

    private func presentAsActive(_ payload: NotchPayload) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.presentAsActive(payload)
            }
            return
        }

        phase = .showing
        closeRequestedWhileBinding = false
        displayToken += 1
        let token = displayToken
        let existingIds = Set(currentNotchWindows().map(ObjectIdentifier.init))

        present(payload: payload)
        bindActiveWindow(for: token, excluding: existingIds, attemptsRemaining: maxBindRetryCount)
    }

    private func enqueue(_ payload: NotchPayload) {
        pendingQueue.append(payload)
        if pendingQueue.count > maxQueueSize {
            pendingQueue.removeFirst(pendingQueue.count - maxQueueSize)
            fputs("cicada-notifier queue overflow, dropped oldest notifications\n", stderr)
        }
    }

    private func currentNotchWindows() -> [NSWindow] {
        NSApplication.shared.windows.filter { isNotchWindow($0) }
    }

    private func currentActiveWindow() -> NSWindow? {
        guard let activeWindow else { return nil }
        return currentNotchWindows().first { ObjectIdentifier($0) == activeWindow.id }
    }

    private func bindActiveWindow(
        for token: UInt64,
        excluding existingIds: Set<ObjectIdentifier>,
        attemptsRemaining: Int
    ) {
        guard token == displayToken else { return }

        let windows = currentNotchWindows()
        let candidate = windows.first { !existingIds.contains(ObjectIdentifier($0)) } ?? windows.last

        if let window = candidate {
            activateWindow(window, token: token)
            return
        }

        if attemptsRemaining <= 0 {
            phase = .idle
            playNextIfPossible()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(bindRetryDelayMs)) { [weak self] in
            self?.bindActiveWindow(
                for: token,
                excluding: existingIds,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func activateWindow(_ window: NSWindow, token: UInt64) {
        let windowId = ObjectIdentifier(window)
        activeWindow = ActiveWindowRef(id: windowId)

        if originalWindowStates[windowId] == nil {
            originalWindowStates[windowId] = WindowState(
                level: window.level,
                collectionBehavior: window.collectionBehavior
            )
            registerCloseObserver(for: window, windowId: windowId)
        }

        applyOverlayLevel(for: token, bringToFront: true)
        scheduleOverlayReapply(for: token, delayMs: overlayReapplyDelayMs, bringToFront: false)

        if closeRequestedWhileBinding {
            closeRequestedWhileBinding = false
            startClosingActiveWindowIfNeeded()
        }
    }

    private func startClosingActiveWindowIfNeeded() {
        guard phase == .showing else { return }
        guard let window = currentActiveWindow() else {
            closeRequestedWhileBinding = true
            return
        }

        phase = .closing
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Double(closeAnimationDurationMs) / 1000
            window.animator().alphaValue = 0
        } completionHandler: {
            window.close()
        }
    }

    private func applyOverlayLevel(for token: UInt64, bringToFront: Bool) {
        guard token == displayToken else { return }
        guard phase == .showing else { return }
        guard let window = currentActiveWindow() else { return }
        elevateWindow(window, bringToFront: bringToFront)
    }

    private func scheduleOverlayReapply(for token: UInt64, delayMs: Int, bringToFront: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak self] in
            self?.applyOverlayLevel(for: token, bringToFront: bringToFront)
        }
    }

    private func elevateWindow(_ window: NSWindow, bringToFront: Bool) {
        let windowId = ObjectIdentifier(window)
        if originalWindowStates[windowId] == nil {
            originalWindowStates[windowId] = WindowState(
                level: window.level,
                collectionBehavior: window.collectionBehavior
            )
            registerCloseObserver(for: window, windowId: windowId)
        }

        window.level = overlayWindowLevel
        window.collectionBehavior.formUnion(overlayCollectionBehavior)
        if bringToFront {
            window.orderFrontRegardless()
        }
        window.ignoresMouseEvents = true
        window.isMovable = false
    }

    private func registerCloseObserver(for window: NSWindow, windowId: ObjectIdentifier) {
        guard windowCloseObservers[windowId] == nil else { return }
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let self, let closingWindow = notification.object as? NSWindow else { return }
            self.handleWindowWillClose(closingWindow)
        }
        windowCloseObservers[windowId] = observer
    }

    private func handleWindowWillClose(_ window: NSWindow) {
        let windowId = ObjectIdentifier(window)
        restoreWindowState(for: window)
        removeCloseObserver(for: windowId)
        let wasActive = activeWindow?.id == windowId

        if wasActive {
            activeWindow = nil
            closeRequestedWhileBinding = false
            phase = .idle
            playNextIfPossible()
        } else {
            pruneStaleWindowStates()
        }
    }

    private func playNextIfPossible() {
        guard phase == .idle else { return }
        guard !pendingQueue.isEmpty else { return }
        let next = pendingQueue.removeFirst()
        presentAsActive(next)
    }

    private func restoreWindowState(for window: NSWindow) {
        let windowId = ObjectIdentifier(window)
        guard let originalState = originalWindowStates.removeValue(forKey: windowId) else { return }

        window.level = originalState.level
        window.collectionBehavior = originalState.collectionBehavior
    }

    private func removeCloseObserver(for windowId: ObjectIdentifier) {
        guard let observer = windowCloseObservers.removeValue(forKey: windowId) else { return }
        NotificationCenter.default.removeObserver(observer)
    }

    private func pruneStaleWindowStates() {
        let activeWindowIds = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        let staleStateKeys = originalWindowStates.keys.filter { !activeWindowIds.contains($0) }
        for key in staleStateKeys {
            originalWindowStates.removeValue(forKey: key)
        }

        let staleObserverKeys = windowCloseObservers.keys.filter { !activeWindowIds.contains($0) }
        for key in staleObserverKeys {
            removeCloseObserver(for: key)
        }
    }

    private func isNotchWindow(_ window: NSWindow) -> Bool {
        let className = NSStringFromClass(type(of: window))
        return className.contains("NotchWindow")
    }
}
