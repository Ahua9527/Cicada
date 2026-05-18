import SwiftUI

enum NotificationLevel: String {
    case info
    case success
    case warning
    case error

    static func from(rawValue: String) -> NotificationLevel {
        NotificationLevel(rawValue: rawValue.lowercased()) ?? .info
    }

    var accent: Color {
        switch self {
        case .info:
            return Color(red: 0.38, green: 0.66, blue: 1.0)
        case .success:
            return Color(red: 0.27, green: 0.84, blue: 0.50)
        case .warning:
            return Color(red: 1.0, green: 0.70, blue: 0.22)
        case .error:
            return Color(red: 0.97, green: 0.38, blue: 0.38)
        }
    }
}

struct NotificationTheme {
    let titleFont: Font
    let messageFont: Font
    let titleColor: Color
    let messageColor: Color
    let bodyVerticalSpacing: CGFloat
    let bodyMinWidth: CGFloat

    static let `default` = NotificationTheme(
        titleFont: .system(size: 14, weight: .semibold, design: .rounded),
        messageFont: .system(size: 12, weight: .medium, design: .rounded),
        titleColor: Color.white.opacity(0.98),
        messageColor: Color.white.opacity(0.80),
        bodyVerticalSpacing: 3,
        bodyMinWidth: 220
    )
}
