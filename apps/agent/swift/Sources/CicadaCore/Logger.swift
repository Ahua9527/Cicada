import Foundation

public enum Logger {
    public static func info(_ scope: String, _ message: String, data: [String: String] = [:]) {
        printLine(level: "INFO", scope: scope, message: message, data: data)
    }

    public static func warn(_ scope: String, _ message: String, data: [String: String] = [:]) {
        printLine(level: "WARN", scope: scope, message: message, data: data)
    }

    public static func error(_ scope: String, _ message: String, data: [String: String] = [:]) {
        fputs(formatLine(level: "ERROR", scope: scope, message: message, data: data) + "\n", stderr)
    }

    private static func printLine(level: String, scope: String, message: String, data: [String: String]) {
        print(formatLine(level: level, scope: scope, message: message, data: data))
    }

    private static func formatLine(level: String, scope: String, message: String, data: [String: String]) -> String {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        if data.isEmpty {
            return "[\(timestamp)] [\(level)] [\(scope)] \(message)"
        }
        let payload = data.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        return "[\(timestamp)] [\(level)] [\(scope)] \(message) \(payload)"
    }
}
