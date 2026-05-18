import Foundation

public enum NotificationTitles {
    public static func command(_ command: String) -> String {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return "Cicada · 命令"
        }
        return "Cicada · 命令 \(normalized)"
    }
}
