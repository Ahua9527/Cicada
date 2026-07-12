import Foundation
import Darwin

protocol SleepHoldServiceClient {
    func createSession(completion: @escaping (Result<String, Error>) -> Void)
    func extendSession(_ sessionId: String, completion: @escaping (Bool) -> Void)
    func terminateSession(_ sessionId: String, completion: @escaping (Bool) -> Void)
}

enum SleepHoldServiceClientError: Error {
    case invalidResponse
    case socketPathTooLong
    case unavailable(String)
}

final class CicadaDaemonSleepHoldServiceClient: SleepHoldServiceClient {
    private enum Action: String, Codable {
        case start = "power_assertion_start"
        case stop = "power_assertion_stop"
    }

    private struct Request: Codable {
        let action: Action
    }

    private struct Response: Codable {
        let ok: Bool
        let code: String?
        let error: String?
    }

    private let socketPath: String
    private let timeoutMs: Int
    private let queue = DispatchQueue(label: "com.cicada.sentinel.sleep-hold-client")

    init(
        socketPath: String = CicadaSentinelPaths.daemonSocketPath(),
        timeoutMs: Int = 1000
    ) {
        self.socketPath = socketPath
        self.timeoutMs = timeoutMs
    }

    func createSession(completion: @escaping (Result<String, Error>) -> Void) {
        send(.start) { result in
            switch result {
            case let .success(response) where response.ok:
                completion(.success("cicada-daemon-power-assertion"))
            case let .success(response):
                completion(.failure(SleepHoldServiceClientError.unavailable(response.error ?? "daemon rejected request")))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func extendSession(_: String, completion: @escaping (Bool) -> Void) {
        send(.start) { result in
            completion((try? result.get().ok) == true)
        }
    }

    func terminateSession(_: String, completion: @escaping (Bool) -> Void) {
        send(.stop) { result in
            completion((try? result.get().ok) == true)
        }
    }

    private func send(
        _ action: Action,
        completion: @escaping (Result<Response, Error>) -> Void
    ) {
        queue.async {
            do {
                completion(.success(try self.sendSync(action)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func sendSync(_ action: Action) throws -> Response {
        var payload = try JSONEncoder().encode(Request(action: action))
        payload.append(0x0A)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw SleepHoldServiceClientError.unavailable("daemon control socket create failed")
        }
        defer { close(fd) }

        var timeout = timeval(tv_sec: Int(timeoutMs / 1000), tv_usec: Int32(timeoutMs % 1000 * 1000))
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        try copySocketPath(socketPath, into: &addr)

        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            throw SleepHoldServiceClientError.unavailable(String(cString: strerror(errno)))
        }

        let sent = payload.withUnsafeBytes {
            Darwin.send(fd, $0.baseAddress, payload.count, 0)
        }
        guard sent > 0 else {
            throw SleepHoldServiceClientError.unavailable("daemon control send failed")
        }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let readSize = recv(fd, &buffer, buffer.count, 0)
        guard readSize > 0 else {
            throw SleepHoldServiceClientError.unavailable("daemon control timeout")
        }

        let raw = String(decoding: buffer.prefix(Int(readSize)), as: UTF8.self)
        let line = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        guard let data = line.data(using: .utf8) else {
            throw SleepHoldServiceClientError.invalidResponse
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func copySocketPath(_ path: String, into addr: inout sockaddr_un) throws {
        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
        if path.utf8.count >= maxPathLength {
            throw SleepHoldServiceClientError.socketPathTooLong
        }

        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            buffer.initializeMemory(as: CChar.self, repeating: 0)
            _ = path.withCString { src in
                strncpy(buffer.baseAddress?.assumingMemoryBound(to: CChar.self), src, maxPathLength - 1)
            }
        }
    }
}

final class URLSessionSleepHoldServiceClient: SleepHoldServiceClient {
    private enum Endpoint {
        static let create = URL(string: "http://127.0.0.1:8180/service/session/create")!
        static let extend = URL(string: "http://127.0.0.1:8180/service/session/extend")!
        static let terminate = URL(string: "http://127.0.0.1:8180/service/session/terminate")!
    }

    func createSession(completion: @escaping (Result<String, Error>) -> Void) {
        let request = makeRequest(url: Endpoint.create)
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let sessionId = self.decodeSessionID(from: data)
            else {
                completion(.failure(SleepHoldServiceClientError.invalidResponse))
                return
            }

            completion(.success(sessionId))
        }
        .resume()
    }

    func extendSession(_ sessionId: String, completion: @escaping (Bool) -> Void) {
        let request = makeRequest(url: Endpoint.extend, body: ExtendRequest(sessionId: sessionId))
        sendStatusRequest(request, completion: completion)
    }

    func terminateSession(_ sessionId: String, completion: @escaping (Bool) -> Void) {
        let request = makeRequest(url: Endpoint.terminate, body: TerminateRequest(sessionId: sessionId))
        sendStatusRequest(request, completion: completion)
    }

    private func makeRequest(url: URL) -> URLRequest {
        makeRequest(url: url, httpBody: nil)
    }

    private func makeRequest<Body: Encodable>(url: URL, body: Body?) -> URLRequest {
        makeRequest(url: url, httpBody: body.flatMap { try? JSONEncoder().encode($0) })
    }

    private func makeRequest(url: URL, httpBody: Data?) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 3
        )
        request.httpMethod = "POST"
        if let httpBody {
            request.httpBody = httpBody
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func sendStatusRequest(_ request: URLRequest, completion: @escaping (Bool) -> Void) {
        URLSession.shared.dataTask(with: request) { _, response, _ in
            completion((response as? HTTPURLResponse)?.statusCode == 200)
        }
        .resume()
    }

    private func decodeSessionID(from data: Data?) -> String? {
        guard let data else { return nil }
        return (try? JSONDecoder().decode(CreateSessionResponse.self, from: data))?.sessionId
    }

    private struct CreateSessionResponse: Decodable {
        let sessionId: String
    }

    private struct ExtendRequest: Codable {
        let sessionId: String
    }

    private struct TerminateRequest: Codable {
        let sessionId: String
    }
}
