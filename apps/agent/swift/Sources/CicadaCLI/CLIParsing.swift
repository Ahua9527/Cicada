import Foundation
import CicadaCore

enum CLICommandRoute: Equatable {
    case setup([String])
    case start
    case stop
    case restart
    case status([String])
    case shortcut([String])
    case run([String])
    case advanced([String])
    case help
    case unknown(String)
}

enum CLICommandRouter {
    static func route(arguments: [String]) -> CLICommandRoute {
        guard let command = arguments.first else {
            return .help
        }

        let remaining = Array(arguments.dropFirst())
        switch command {
        case "setup": return .setup(remaining)
        case "start": return .start
        case "stop": return .stop
        case "restart": return .restart
        case "status": return .status(remaining)
        case "shortcut": return .shortcut(remaining)
        case "run": return .run(remaining)
        case "advanced": return .advanced(remaining)
        case "--help", "-h", "help": return .help
        default: return .unknown(command)
        }
    }
}

struct ShortcutCreateArguments: Equatable {
    let name: String
    let commands: [String]
    let ttlMs: Int64
}

enum CLIArgumentParser {
    static func shortcutCreate(_ arguments: [String]) throws -> ShortcutCreateArguments {
        var name = "Shortcut"
        var commands = ["ping", "status"]
        var ttl: String?
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--name":
                guard index + 1 < arguments.count else {
                    throw CLIArgumentError.message("--name 需要值")
                }
                name = arguments[index + 1]
                index += 2
            case "--commands":
                guard index + 1 < arguments.count else {
                    throw CLIArgumentError.message("--commands 需要值")
                }
                commands = ShortcutGrantStore.normalizeCommands(
                    arguments[index + 1].split(separator: ",").map(String.init)
                )
                index += 2
            case "--ttl":
                guard index + 1 < arguments.count else {
                    throw CLIArgumentError.message("--ttl 需要值")
                }
                ttl = arguments[index + 1]
                index += 2
            default:
                throw CLIArgumentError.message("未知参数: \(arguments[index])")
            }
        }

        return ShortcutCreateArguments(
            name: name,
            commands: commands,
            ttlMs: durationMilliseconds(ttl)
        )
    }

    static func durationMilliseconds(_ raw: String?) -> Int64 {
        guard let raw, !raw.isEmpty else {
            return ShortcutGrantStore.defaultTtlMs
        }
        if let days = Int64(String(raw.dropLast())), raw.hasSuffix("d") {
            return days * 24 * 60 * 60 * 1000
        }
        if let hours = Int64(String(raw.dropLast())), raw.hasSuffix("h") {
            return hours * 60 * 60 * 1000
        }
        if let minutes = Int64(String(raw.dropLast())), raw.hasSuffix("m") {
            return minutes * 60 * 1000
        }
        return Int64(raw) ?? ShortcutGrantStore.defaultTtlMs
    }

    static func optionalValue(_ arguments: [String], flag: String) throws -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        guard index + 1 < arguments.count else {
            throw CLIArgumentError.message("\(flag) 需要值")
        }
        return arguments[index + 1]
    }

    static func firstUnknownFlag(_ arguments: [String], allowed: Set<String>) -> String? {
        var index = 0
        while index < arguments.count {
            let item = arguments[index]
            if item.hasPrefix("--") {
                if !allowed.contains(item) { return item }
                index += 2
            } else {
                return item
            }
        }
        return nil
    }
}

enum CLIOutputFormatter {
    static func json(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}

enum CLIArgumentError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(message):
            return message
        }
    }
}
