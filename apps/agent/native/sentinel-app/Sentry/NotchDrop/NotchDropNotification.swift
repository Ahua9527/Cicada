import SwiftUI

enum NotchDropNotificationLevel: String, Codable, Equatable {
    case info
    case success
    case warning
    case error

    static func from(rawValue: String) -> NotchDropNotificationLevel {
        NotchDropNotificationLevel(rawValue: rawValue.lowercased()) ?? .info
    }

    var accent: Color {
        switch self {
        case .info:
            Color(red: 0.38, green: 0.66, blue: 1.0)
        case .success:
            Color(red: 0.27, green: 0.84, blue: 0.50)
        case .warning:
            Color(red: 1.0, green: 0.70, blue: 0.22)
        case .error:
            Color(red: 0.97, green: 0.38, blue: 0.38)
        }
    }
}

struct NotchDropNotificationPayload: Equatable {
    let level: NotchDropNotificationLevel
    let title: String
    let message: String?
    let durationMs: Int
}

@MainActor
protocol SentinelNotificationRendering: AnyObject {
    func render(_ payload: NotchDropNotificationPayload)
}

@MainActor
protocol NotchDropPresenting: AnyObject {
    func presentNotification(_ payload: NotchDropNotificationPayload, completion: @escaping () -> Void)
}

struct NotchDropNotificationView: View {
    let payload: NotchDropNotificationPayload
    let vm: NotchViewModel

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(payload.level.accent)
                .frame(width: 12, height: 12)
                .shadow(color: payload.level.accent.opacity(0.8), radius: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(payload.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                if let message = payload.message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: vm.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: vm.cornerRadius, style: .continuous)
                        .stroke(payload.level.accent.opacity(0.35), lineWidth: 1)
                )
        )
    }
}
