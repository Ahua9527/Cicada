import AppKit
import Foundation

final class NativeAppController: NativeAppControlling {
    /// 打开闭包：镜像 `NSWorkspace.openApplication` 的异步回调语义，
    /// 完成时回调 error（nil 表示成功）。内部可注入，单测可模拟成功/错误/永不回调。
    typealias OpenHandler = (URL, @escaping (Error?) -> Void) -> Void

    private let workspace: NSWorkspace
    private let bundleIDResolver: (String) -> URL?
    private let searchRoots: [String]
    private let openTimeout: TimeInterval
    private let opener: OpenHandler

    /// 默认递归搜索根目录。
    static var defaultSearchRoots: [String] {
        ["/Applications", "/System/Applications", "\(NSHomeDirectory())/Applications"]
    }

    /// 应用解析器（bundle id 查询）、打开闭包、搜索根目录与超时均为内部可注入依赖；
    /// 缺省时取 NSWorkspace 真实行为与默认搜索根。
    init(
        workspace: NSWorkspace = .shared,
        bundleIDResolver: ((String) -> URL?)? = nil,
        searchRoots: [String]? = nil,
        openTimeout: TimeInterval = 15,
        opener: OpenHandler? = nil
    ) {
        self.workspace = workspace
        self.bundleIDResolver = bundleIDResolver ?? { workspace.urlForApplication(withBundleIdentifier: $0) }
        self.searchRoots = searchRoots ?? Self.defaultSearchRoots
        self.openTimeout = openTimeout
        self.opener = opener ?? { url, completion in
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                completion(error)
            }
        }
    }

    func openApplication(named name: String) -> Result<Void, NativeCommandError> {
        guard let url = appURL(for: name) else {
            return .failure(.message("找不到应用: \(name)"))
        }
        let semaphore = DispatchSemaphore(value: 0)
        var openError: Error?
        opener(url) { error in
            openError = error
            semaphore.signal()
        }
        // 等不到回调必须明确失败——超时不报会让用户误以为应用已打开。
        guard semaphore.wait(timeout: .now() + openTimeout) != .timedOut else {
            return .failure(.message("打开应用超时: \(url.deletingPathExtension().lastPathComponent)"))
        }
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

    /// 先按 bundle id 查询（LaunchServices 精确匹配，支持仅知 bundle id 的调用方），
    /// 未命中再按应用名递归搜索安装目录。
    private func appURL(for name: String) -> URL? {
        if let url = bundleIDResolver(name) {
            return url
        }
        return Self.findApp(named: name, searchRoots: searchRoots)
    }

    /// 按应用名递归搜索（跳过隐藏文件与 .app 包内部），
    /// 覆盖 /System/Applications/Utilities/Terminal.app 这类嵌套应用。
    static func findApp(
        named name: String,
        searchRoots: [String],
        fileManager: FileManager = .default
    ) -> URL? {
        let needle = name.lowercased()
        for root in searchRoots {
            guard let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "app" {
                if url.deletingPathExtension().lastPathComponent.lowercased() == needle {
                    return url
                }
            }
        }
        return nil
    }
}
