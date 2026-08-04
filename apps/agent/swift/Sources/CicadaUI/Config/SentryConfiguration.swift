import Foundation

/// Cicada 的防护层配置。
public struct SentryConfiguration: Codable, Equatable, Hashable {
    public var sentryTriggersLidEnabled: Bool
    public var sentryTriggersInternetEnabled: Bool
    public var sentryTriggersPowerEnabled: Bool

    public var sentryAlarmsSoundsEnabled: Bool
    public var sentryAlarmsNotificationType: NotificationType
    public var sentryNotificationConfigBark: NotificationConfiguration_Bark
    public var sentryRecordingEnabled: Bool
    public var sentryRecordingDevice: String?

    public enum NotificationType: String, Codable, Equatable, Hashable {
        case none
        case bark
    }

    public struct NotificationConfiguration_Bark: Codable, Equatable, Hashable {
        public var endpoint: String

        public init(endpoint: String = "https://") {
            self.endpoint = endpoint
        }
    }

    public init(
        sentryTriggersLidEnabled: Bool = false,
        sentryTriggersInternetEnabled: Bool = false,
        sentryTriggersPowerEnabled: Bool = false,
        sentryAlarmsSoundsEnabled: Bool = false,
        sentryAlarmsNotificationType: NotificationType = .none,
        sentryNotificationConfigBark: NotificationConfiguration_Bark = .init(),
        sentryRecordingEnabled: Bool = false,
        sentryRecordingDevice: String? = nil
    ) {
        self.sentryTriggersLidEnabled = sentryTriggersLidEnabled
        self.sentryTriggersInternetEnabled = sentryTriggersInternetEnabled
        self.sentryTriggersPowerEnabled = sentryTriggersPowerEnabled
        self.sentryAlarmsSoundsEnabled = sentryAlarmsSoundsEnabled
        self.sentryAlarmsNotificationType = sentryAlarmsNotificationType
        self.sentryNotificationConfigBark = sentryNotificationConfigBark
        self.sentryRecordingEnabled = sentryRecordingEnabled
        self.sentryRecordingDevice = sentryRecordingDevice
    }

    // MARK: - 计算属性（从现有 SentryConfigurationManager 提取）

    /// 是否有任意触发器已启用。
    public var hasTriggerEnabled: Bool {
        enabledTriggerCount > 0
    }

    /// 已启用的触发器数量（lid / internet / power）。
    public var enabledTriggerCount: Int {
        var count = 0
        if sentryTriggersLidEnabled { count += 1 }
        if sentryTriggersInternetEnabled { count += 1 }
        if sentryTriggersPowerEnabled { count += 1 }
        return count
    }

    /// 是否有通知方式已配置。
    public var hasNotificationEnabled: Bool {
        sentryAlarmsNotificationType != .none || sentryAlarmsSoundsEnabled
    }

    /// 是否已启用录像。
    public var hasRecordingEnabled: Bool {
        sentryRecordingEnabled
    }

    /// 是否满足激活条件（触发器 + 通知都就绪）。
    public var canActivate: Bool {
        hasTriggerEnabled && hasNotificationEnabled
    }
}
