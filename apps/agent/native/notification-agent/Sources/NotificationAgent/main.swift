import AppKit
import Darwin
import Foundation

private struct NotifyRequest: Codable {
    let version: Int
    let id: String
    let source: String
    let style: String
    let level: String
    let title: String
    let message: String?
    let durationMs: Int?
    let timestamp: Int64
}

private struct NotifyResponse: Codable {
    let ok: Bool
    let code: String?
    let error: String?
}

private final class UnixSocketServer {
    private let socketPath: String
    private let renderer: NotchRenderer
    private let queue = DispatchQueue(label: "com.cicada.notifier.socket", qos: .userInitiated)
    private var serverFD: Int32 = -1

    init(socketPath: String, renderer: NotchRenderer) {
        self.socketPath = socketPath
        self.renderer = renderer
    }

    func start() throws {
        try ensureSocketParentDirectory()
        unlink(socketPath)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            throw NSError(
                domain: "Notifier",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "socket creation failed"]
            )
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let pathBytes = socketPath.utf8CString
        if pathBytes.count >= maxLen {
            throw NSError(
                domain: "Notifier",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "socket path too long"]
            )
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: maxLen) { pathPtr in
                _ = pathBytes.withUnsafeBufferPointer { buffer in
                    strncpy(pathPtr, buffer.baseAddress, maxLen - 1)
                }
            }
        }

        var bindAddr = sockaddr()
        memcpy(&bindAddr, &addr, MemoryLayout<sockaddr_un>.size)

        let bindResult = withUnsafePointer(to: &bindAddr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            throw NSError(
                domain: "Notifier",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "bind failed"]
            )
        }

        chmod(socketPath, 0o600)

        guard listen(serverFD, 16) == 0 else {
            throw NSError(
                domain: "Notifier",
                code: 1004,
                userInfo: [NSLocalizedDescriptionKey: "listen failed"]
            )
        }

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    private func acceptLoop() {
        while true {
            let clientFD = accept(serverFD, nil, nil)
            if clientFD < 0 {
                continue
            }

            handle(clientFD: clientFD)
            close(clientFD)
        }
    }

    private func handle(clientFD: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let readSize = recv(clientFD, &buffer, buffer.count, 0)

        guard readSize > 0 else {
            writeResponse(
                clientFD: clientFD,
                response: NotifyResponse(ok: false, code: "INVALID_PAYLOAD", error: "empty payload")
            )
            return
        }

        let raw = String(decoding: buffer.prefix(Int(readSize)), as: UTF8.self)
        let line = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first ?? ""

        guard let data = line.data(using: .utf8) else {
            writeResponse(
                clientFD: clientFD,
                response: NotifyResponse(ok: false, code: "INVALID_PAYLOAD", error: "invalid utf8")
            )
            return
        }

        do {
            let request = try JSONDecoder().decode(NotifyRequest.self, from: data)
            guard validate(request: request) else {
                writeResponse(
                    clientFD: clientFD,
                    response: NotifyResponse(ok: false, code: "INVALID_PAYLOAD", error: "invalid request")
                )
                return
            }

            let duration = max(request.durationMs ?? 2500, 500)
            DispatchQueue.main.async { [weak self] in
                self?.renderer.render(
                    level: request.level,
                    title: request.title,
                    message: request.message,
                    durationMs: duration
                )
            }

            writeResponse(clientFD: clientFD, response: NotifyResponse(ok: true, code: nil, error: nil))
        } catch {
            writeResponse(
                clientFD: clientFD,
                response: NotifyResponse(ok: false, code: "INVALID_PAYLOAD", error: "decode failed")
            )
        }
    }

    private func validate(request: NotifyRequest) -> Bool {
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return request.version == 1
            && request.style == "dynamic_island"
            && !title.isEmpty
    }

    private func writeResponse(clientFD: Int32, response: NotifyResponse) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        let payload = data + Data("\n".utf8)

        _ = payload.withUnsafeBytes { buffer in
            send(clientFD, buffer.baseAddress, payload.count, 0)
        }
    }

    private func ensureSocketParentDirectory() throws {
        let parent = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var server: UnixSocketServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let socketPath = ProcessInfo.processInfo.environment["CICADA_NOTIFIER_SOCKET"]
            ?? (NSHomeDirectory() + "/.cicada/run/notifier.sock")

        let renderer = NotchRenderer()
        let server = UnixSocketServer(socketPath: socketPath, renderer: renderer)

        do {
            try server.start()
            self.server = server
        } catch {
            fputs("cicada-notifier failed to start: \(error)\n", stderr)
            NSApp.terminate(nil)
        }
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
