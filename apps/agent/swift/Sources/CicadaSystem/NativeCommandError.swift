import Foundation

enum NativeCommandError: Error {
    case message(String)

    var message: String {
        switch self {
        case let .message(text):
            return text
        }
    }
}
