import Foundation

public enum CicadaError: Error, CustomStringConvertible {
    case validation(String)
    case io(String)
    case command(String)
    case runtime(String)

    public var description: String {
        switch self {
        case let .validation(message):
            return message
        case let .io(message):
            return message
        case let .command(message):
            return message
        case let .runtime(message):
            return message
        }
    }
}
