import AppKit
import Foundation

final class NativeAppController: NativeAppControlling {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func openApplication(named name: String) -> Result<Void, NativeCommandError> {
        guard let url = appURL(for: name) else {
            return .failure(.message("找不到应用: \(name)"))
        }
        let semaphore = DispatchSemaphore(value: 0)
        var openError: Error?
        workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            openError = error
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 15)
        if let openError {
            return .failure(.message("打开应用失败: \(openError.localizedDescription)"))
        }
        return .success(())
    }

    func closeApplication(named name: String) -> Result<Void, NativeCommandError> {
        let matches = runningRegularApps(named: name)
        guard let app = matches.first else {
            return .failure(.message("应用未在运行: \(name)"))
        }
        return app.terminate()
            ? .success(())
            : .failure(.message("关闭应用失败: \(name)"))
    }

    func switchToApplication(named name: String) -> Result<Void, NativeCommandError> {
        let matches = runningRegularApps(named: name)
        guard let app = matches.first else {
            return .failure(.message("应用未在运行: \(name)"))
        }
        return app.activate(options: [.activateIgnoringOtherApps])
            ? .success(())
            : .failure(.message("切换应用失败: \(name)"))
    }

    func listRunningApplications() -> [String] {
        workspace.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName)
            .sorted()
    }

    private func runningRegularApps(named name: String) -> [NSRunningApplication] {
        let needle = name.lowercased()
        return workspace.runningApplications.filter { app in
            guard app.activationPolicy == .regular else { return false }
            return app.localizedName?.lowercased() == needle
                || app.bundleIdentifier?.lowercased() == needle
        }
    }

    private func appURL(for name: String) -> URL? {
        let needle = name.lowercased()
        let fileManager = FileManager.default
        for directory in ["/Applications", "/System/Applications", "\(NSHomeDirectory())/Applications"] {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let appName = String(entry.dropLast(4))
                if appName.lowercased() == needle {
                    return URL(fileURLWithPath: "\(directory)/\(entry)")
                }
            }
        }
        return workspace.urlForApplication(withBundleIdentifier: name)
    }
}
