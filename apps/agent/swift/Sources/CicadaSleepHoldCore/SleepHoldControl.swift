import Foundation

public enum SleepHoldPowerStatus: String, Codable, Equatable {
    case canSleep = "sleep_enabled"
    case hold = "sleep_disabled"
    case unknown
}
public enum SleepHoldControlAction: String, Codable, Equatable {
    case ping
    case status
    case sessionCreate = "session_create"
    case sessionExtend = "session_extend"
    case sessionTerminate = "session_terminate"
}

public struct SleepHoldControlRequest: Codable, Equatable {
    public let action: SleepHoldControlAction
    public let sessionId: String?

    public init(action: SleepHoldControlAction, sessionId: String? = nil) {
        self.action = action
        self.sessionId = sessionId
    }
}

public struct SleepHoldControlResponse: Codable, Equatable {
    public let ok: Bool
    public let code: String?
    public let error: String?
    public let message: String?
    public let sessionId: String?
    public let status: SleepHoldPowerStatus?
    public let activeSessions: Int?

    public init(
        ok: Bool,
        code: String? = nil,
        error: String? = nil,
        message: String? = nil,
        sessionId: String? = nil,
        status: SleepHoldPowerStatus? = nil,
        activeSessions: Int? = nil
    ) {
        self.ok = ok
        self.code = code
        self.error = error
        self.message = message
        self.sessionId = sessionId
        self.status = status
        self.activeSessions = activeSessions
    }
}
