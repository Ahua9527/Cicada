import Dispatch
import CicadaCore
import Foundation

enum NotchDropPaths {
    static let defaultStorageDirectory = storageDirectory()

    static func storageDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = RuntimePaths.home
    ) -> URL {
        CicadaSentinelPaths.notchDropDirectory(
            environment: environment,
            homeDirectory: homeDirectory
        )
    }

    static let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.cicada.sentinel", isDirectory: true)
        .appendingPathComponent("NotchDrop", isDirectory: true)
}

let productPage = URL(string: "https://github.com/Lakr233/NotchDrop")!
let sponsorPage = URL(string: "https://github.com/sponsors/Lakr233")!
let documentsDirectory = NotchDropPaths.defaultStorageDirectory
let temporaryDirectory = NotchDropPaths.temporaryDirectory

extension DispatchQueue {
    func asyncAndWait(_ work: @escaping () -> Void) {
        if self === DispatchQueue.main, Thread.isMainThread {
            work()
        } else {
            sync(execute: work)
        }
    }
}
