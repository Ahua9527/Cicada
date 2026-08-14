import Foundation
import CicadaCore
import CicadaIPC
import CicadaSystem

public protocol CommandExecuting {
    func execute(command rawCommand: String) -> CommandExecutionResult
    func execute(command rawCommand: String, params: [String: String]) -> CommandExecutionResult
}

public protocol NotifierSending {
    func notifyQuick(
        source: String,
        level: NotificationLevel,
        title: String,
        message: String?,
        durationMs: Int?
    ) -> NotifyResponse
}

extension MacOSCommandGateway: CommandExecuting {
    public func execute(command rawCommand: String, params: [String: String]) -> CommandExecutionResult {
        execute(command: rawCommand, params: params as [String: Any])
    }
}
extension UdsNotifier: NotifierSending {}

public enum RelayConnectionState: String, Codable {
    case idle
    case connecting
    case connected
    case reconnectWait = "reconnect_wait"
    case stopped
}

private struct DaemonRuntimeEffectiveConfig: Codable {
    let autoConnect: Bool
    let showNotifications: Bool
    let enableAutoReconnect: Bool
    let reconnectInterval: Int
    let maxReconnectAttempts: Int
    let heartbeatInterval: Int
    let connectionTimeout: Int
}

private struct DaemonRuntimeSnapshot: Codable {
    let mode: String
    let connectionState: String
    let updatedAt: Int64
    let effectiveConfig: DaemonRuntimeEffectiveConfig
    let nativeCapabilities: NativeCapabilitySnapshot?
}

public final class RelayDaemonService: NSObject {
    private let config: CicadaConfig
    private let commandGateway: any CommandExecuting
    private let notifier: any NotifierSending
    private let identityStore: RelayIdentityStore
    private let shortcutGrantStore: ShortcutGrantStore

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var identity: RelayIdentity?
    private var liveSessionId: String?
    private var pingTimer: DispatchSourceTimer?
    private var healthTimer: DispatchSourceTimer?
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectAttempts = 0
    private var lastPongAt = Date.distantPast
    private var isStopping = false
    public private(set) var connectionState: RelayConnectionState = .stopped
#if DEBUG
    private var debugOutgoingMessagesStorage: [String] = []
#endif

    public init(
        config: CicadaConfig,
        commandGateway: any CommandExecuting,
        notifier: any NotifierSending,
        identityStore: RelayIdentityStore = RelayIdentityStore(),
        shortcutGrantStore: ShortcutGrantStore = ShortcutGrantStore()
    ) {
        self.config = config
        self.commandGateway = commandGateway
        self.notifier = notifier
        self.identityStore = identityStore
        self.shortcutGrantStore = shortcutGrantStore
        super.init()
    }

    public var mode: String {
        config.autoConnect ? "connected" : "idle"
    }

    public func start() {
        isStopping = false
        if config.autoConnect {
            connect()
            return
        }

        transition(to: .idle, reason: "auto_connect_disabled")
    }

    public func stop() {
        isStopping = true
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        pingTimer?.cancel()
        pingTimer = nil
        healthTimer?.cancel()
        healthTimer = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        transition(to: .stopped, reason: "service_stopped")
    }

    public func createShortcutGrant(
        name: String,
        commands: [String],
        ttlMs: Int64 = ShortcutGrantStore.defaultTtlMs
    ) throws -> ShortcutGrantCreateResult {
        let result = try shortcutGrantStore.create(
            deviceId: config.deviceId,
            name: name,
            commands: commands,
            ttlMs: ttlMs
        )
        sendShortcutGrantUpdate(state: "active", grant: result.grant)
        return result
    }

    public func listShortcutGrants() throws -> [ShortcutGrant] {
        try shortcutGrantStore.list()
    }

    public func revokeShortcutGrant(grantId: String) throws -> ShortcutGrant {
        let grant = try shortcutGrantStore.revoke(grantId: grantId)
        sendShortcutGrantUpdate(state: "revoked", grant: grant)
        return grant
    }

    public func executeLocalCommand(_ command: String) -> CommandExecutionResult {
        handleCommand(command, commandId: "daemon-control")
    }

    private func connect() {
        guard !isStopping else { return }
        guard task == nil else { return }

        let identity: RelayIdentity
        do {
            identity = try identityStore.loadOrCreate(identityId: config.deviceId)
            self.identity = identity
        } catch {
            Logger.error("RelayDaemon", "identity load failed", data: ["error": String(describing: error)])
            scheduleReconnect(reason: "identity_load_failed")
            return
        }

        let liveSessionId = "live-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        self.liveSessionId = liveSessionId

        guard let request = RelayURLBuilder.buildAgentWebSocketRequest(
            config: config,
            liveSessionId: liveSessionId,
            identity: identity
        ) else {
            Logger.error("RelayDaemon", "invalid relayURL", data: ["relayURL": config.relayURL])
            scheduleReconnect(reason: "invalid_relay_url")
            return
        }

        transition(to: .connecting, reason: "connect")

        let timeoutSeconds = max(1.0, Double(config.connectionTimeout) / 1000.0)
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = timeoutSeconds
        sessionConfig.timeoutIntervalForResource = max(5.0, timeoutSeconds * 2.0)

        let session = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
        self.session = session

        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()

        startReceiveLoop()
    }

    private func startReceiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case let .success(message):
                self.handleMessage(message)
                self.startReceiveLoop()
            case let .failure(error):
                Logger.warn("RelayDaemon", "websocket receive failed", data: ["error": error.localizedDescription])
                self.handleDisconnected(reason: "receive_failed")
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let raw: String
        switch message {
        case let .string(text):
            raw = text
        case let .data(data):
            raw = String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return
        }

        processRawMessage(raw)
    }

    private func processRawMessage(_ raw: String) {
        if RelayMessageCodec.isPong(raw) {
            lastPongAt = Date()
            return
        }

        if let acknowledgement = RelayMessageCodec.shortcutGrantUpdateAcknowledgement(raw) {
            if !acknowledgement.accepted {
                Logger.warn(
                    "RelayDaemon",
                    "shortcut grant update rejected",
                    data: ["code": acknowledgement.code]
                )
            }
            return
        }

        if processShortcutCommand(raw) {
            return
        }
    }

    private func processShortcutCommand(_ raw: String) -> Bool {
        guard let incoming = RelayMessageCodec.shortcutCommand(raw) else { return false }
        let authorization = shortcutGrantStore.authorize(
            grantId: incoming.grantId,
            command: incoming.command
        )
        guard authorization.allowed else {
            sendShortcutResult(
                requestId: incoming.requestId,
                command: incoming.command,
                ok: false,
                success: false,
                message: authorization.error ?? "Shortcut grant rejected.",
                code: authorization.code,
                error: authorization.error
            )
            return true
        }

        let result = handleCommand(
            incoming.command,
            commandId: incoming.requestId.isEmpty ? "shortcut" : incoming.requestId,
            params: incoming.params
        )
        sendShortcutResult(
            requestId: incoming.requestId,
            command: incoming.command,
            ok: true,
            success: result.success,
            message: result.message,
            data: result.data
        )
        return true
    }

    @discardableResult
    private func handleCommand(
        _ command: String,
        commandId: String,
        params: [String: String] = [:]
    ) -> CommandExecutionResult {
        let result = params.isEmpty
            ? commandGateway.execute(command: command)
            : commandGateway.execute(command: command, params: params)
        if config.showNotifications {
            let level: NotificationLevel = result.success ? .success : .error
            let title = NotificationTitles.command(command)
            _ = notifier.notifyQuick(
                source: "daemon",
                level: level,
                title: title,
                message: result.message,
                durationMs: 2500
            )
        }

        appendDaemonLog(command: command, result: result)
        return result
    }

    private func sendShortcutResult(
        requestId: String,
        command: String,
        ok: Bool,
        success: Bool,
        message: String,
        data: [String: String]? = nil,
        code: String? = nil,
        error: String? = nil
    ) {
        guard let text = RelayMessageCodec.shortcutResult(
            requestId: requestId,
            command: command,
            ok: ok,
            success: success,
            message: message,
            data: data,
            code: code,
            error: error,
            sentAt: Int64(Date().timeIntervalSince1970 * 1000)
        ) else { return }
        sendRelayText(text)
    }

    private func appendDaemonLog(command: String, result: CommandExecutionResult) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(result.success ? "INFO" : "ERROR")] cmd=\(command) message=\(result.message)\n"
        if FileManager.default.fileExists(atPath: RuntimePaths.daemonLogPath) {
            if let handle = FileHandle(forWritingAtPath: RuntimePaths.daemonLogPath) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    try? handle.write(contentsOf: data)
                }
            }
            return
        }

        try? line.write(toFile: RuntimePaths.daemonLogPath, atomically: true, encoding: .utf8)
    }

    private func handleConnected() {
        reconnectAttempts = 0
        lastPongAt = Date()
        startPingLoop()
        startHealthLoop()
        transition(to: .connected, reason: "connected")
        publishActiveShortcutGrants()
        Logger.info("RelayDaemon", "connected", data: ["deviceId": config.deviceId])
        if config.showNotifications {
            _ = notifier.notifyQuick(
                source: "daemon",
                level: .success,
                title: "Cicada 已连接",
                message: config.deviceId,
                durationMs: 2500
            )
        }
    }

    private func publishActiveShortcutGrants() {
        guard let grants = try? shortcutGrantStore.activeGrants() else {
            return
        }
        for grant in grants {
            sendShortcutGrantUpdate(state: "active", grant: grant)
        }
    }

    private func handleDisconnected(reason: String) {
        pingTimer?.cancel()
        pingTimer = nil
        healthTimer?.cancel()
        healthTimer = nil

        task?.cancel(with: .goingAway, reason: nil)
        task = nil

        session?.invalidateAndCancel()
        session = nil

        switch RelayConnectionLifecycle.disconnectionAction(
            isStopping: isStopping,
            autoConnect: config.autoConnect,
            enableAutoReconnect: config.enableAutoReconnect
        ) {
        case .stop:
            transition(to: .stopped, reason: reason)
        case .reconnect:
            scheduleReconnect(reason: reason)
        }
    }

    private func scheduleReconnect(reason: String) {
        guard !isStopping else { return }
        reconnectWorkItem?.cancel()
        switch RelayConnectionLifecycle.reconnectDecision(
            currentAttempts: reconnectAttempts,
            maxAttempts: config.maxReconnectAttempts,
            reconnectIntervalMs: config.reconnectInterval
        ) {
        case let .stop(attempt):
            reconnectAttempts = attempt
            Logger.error("RelayDaemon", "reconnect attempts exceeded", data: ["attempts": String(attempt)])
            transition(to: .stopped, reason: "reconnect_attempts_exceeded")
        case let .reconnect(attempt, delayMs):
            reconnectAttempts = attempt
            transition(to: .reconnectWait, reason: reason)
            Logger.warn("RelayDaemon", "schedule reconnect", data: ["delayMs": String(delayMs), "attempt": String(attempt)])

            let workItem = DispatchWorkItem { [weak self] in
                self?.connect()
            }
            reconnectWorkItem = workItem
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(delayMs), execute: workItem)
        }
    }

    private func startPingLoop() {
        pingTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + .seconds(config.heartbeatInterval / 1000), repeating: .seconds(config.heartbeatInterval / 1000))
        timer.setEventHandler { [weak self] in
            self?.sendPing()
        }
        timer.resume()

        pingTimer = timer
    }

    private func startHealthLoop() {
        healthTimer?.cancel()

        let intervalSeconds = max(1, config.connectionTimeout / 1000)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + .seconds(intervalSeconds), repeating: .seconds(intervalSeconds))
        timer.setEventHandler { [weak self] in
            self?.checkConnectionHealth()
        }
        timer.resume()

        healthTimer = timer
    }

    private func sendPing() {
        guard let text = RelayMessageCodec.ping(
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        ) else { return }
        sendRelayText(text)
    }

    private func sendShortcutGrantUpdate(state: String, grant: ShortcutGrant) {
        guard let text = RelayMessageCodec.shortcutGrantUpdate(
            state: state,
            grant: grant,
            sentAt: Int64(Date().timeIntervalSince1970 * 1000)
        ) else { return }
        sendRelayText(text)
    }

    private func sendRelayText(_ text: String) {
#if DEBUG
        if task == nil {
            debugOutgoingMessagesStorage.append(text)
            return
        }
#endif
        task?.send(.string(text)) { [weak self] error in
            if let error {
                Logger.warn("RelayDaemon", "websocket send failed", data: ["error": error.localizedDescription])
                self?.handleDisconnected(reason: "send_failed")
            }
        }
    }

    private func checkConnectionHealth(now: Date = Date()) {
        guard connectionState == .connected else { return }

        if !RelayConnectionLifecycle.isPongTimedOut(
            lastPongAt: lastPongAt,
            now: now,
            timeoutMs: config.connectionTimeout
        ) {
            return
        }

        let elapsedMs = now.timeIntervalSince(lastPongAt) * 1000

        Logger.warn(
            "RelayDaemon",
            "pong timeout",
            data: [
                "elapsedMs": String(Int(elapsedMs)),
                "connectionTimeout": String(config.connectionTimeout),
            ]
        )
        handleDisconnected(reason: "pong_timeout")
    }

    private func transition(to newState: RelayConnectionState, reason: String) {
        if connectionState != newState {
            connectionState = newState
            Logger.info("RelayDaemon", "state changed", data: ["state": newState.rawValue, "reason": reason])
        }
        persistRuntimeSnapshot()
    }

    private func persistRuntimeSnapshot() {
        let snapshot = DaemonRuntimeSnapshot(
            mode: mode,
            connectionState: connectionState.rawValue,
            updatedAt: Int64(Date().timeIntervalSince1970 * 1000),
            effectiveConfig: DaemonRuntimeEffectiveConfig(
                autoConnect: config.autoConnect,
                showNotifications: config.showNotifications,
                enableAutoReconnect: config.enableAutoReconnect,
                reconnectInterval: config.reconnectInterval,
                maxReconnectAttempts: config.maxReconnectAttempts,
                heartbeatInterval: config.heartbeatInterval,
                connectionTimeout: config.connectionTimeout
            ),
            nativeCapabilities: (commandGateway as? MacOSCommandGateway)?.nativeCapabilitySnapshot()
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            let directory = (RuntimePaths.daemonStatePath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: RuntimePaths.daemonStatePath), options: .atomic)
            _ = chmod(RuntimePaths.daemonStatePath, 0o600)
        } catch {
            Logger.warn("RelayDaemon", "failed to persist runtime snapshot", data: ["error": error.localizedDescription])
        }
    }

#if DEBUG
    func debugHandleRawMessage(_ raw: String) {
        processRawMessage(raw)
    }

    func debugOutgoingMessages() -> [String] {
        debugOutgoingMessagesStorage
    }

    func debugSetLastPong(_ date: Date) {
        lastPongAt = date
    }

    func debugSetConnectionState(_ state: RelayConnectionState) {
        transition(to: state, reason: "debug_set_state")
    }

    func debugCheckConnectionHealth(now: Date = Date()) {
        checkConnectionHealth(now: now)
    }
#endif
}

extension RelayDaemonService: URLSessionWebSocketDelegate {
    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        handleConnected()
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Logger.warn("RelayDaemon", "websocket closed", data: ["code": String(closeCode.rawValue)])
        let rawCode = closeCode.rawValue
        let reasonPrefix = RelayCloseCodes.isRetryableAgentAbsence(rawCode)
            ? "agent_retryable_absence"
            : "websocket_closed"
        handleDisconnected(reason: "\(reasonPrefix)_\(rawCode)")
    }
}
