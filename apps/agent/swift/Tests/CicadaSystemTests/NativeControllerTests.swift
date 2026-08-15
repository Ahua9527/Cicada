import Carbon
import CoreGraphics
import Foundation
import XCTest
@testable import CicadaSystem

final class NativePowerControllerTests: XCTestCase {
    func testRestartEventTargetsLoginWindowWithFinderSuite() {
        let descriptor = NativePowerController.makeLoginWindowEvent(AEEventID(kAERestart))

        XCTAssertEqual(descriptor.eventClass, AEEventClass(kAEFinderEvents))
        XCTAssertEqual(descriptor.eventID, AEEventID(kAERestart))
        XCTAssertEqual(Self.targetBundleID(of: descriptor), "com.apple.loginwindow")
    }

    func testShutdownEventTargetsLoginWindowWithFinderSuite() {
        let descriptor = NativePowerController.makeLoginWindowEvent(AEEventID(kAEShutDown))

        XCTAssertEqual(descriptor.eventClass, AEEventClass(kAEFinderEvents))
        XCTAssertEqual(descriptor.eventID, AEEventID(kAEShutDown))
        XCTAssertEqual(Self.targetBundleID(of: descriptor), "com.apple.loginwindow")
    }

    private static func targetBundleID(of descriptor: NSAppleEventDescriptor) -> String? {
        descriptor.attributeDescriptor(forKeyword: AEKeyword(keyAddressAttr))
            .map { String(decoding: $0.data, as: UTF8.self) }
    }
}

final class NativeDisplayControllerTests: XCTestCase {
    func testBrightnessServicesReceiveMainDisplayIDAndValues() {
        var getIDs: [CGDirectDisplayID] = []
        var setCalls: [(CGDirectDisplayID, Float)] = []
        let services = NativeDisplayController.BrightnessServices(
            get: { id, pointer in
                getIDs.append(id)
                pointer.pointee = 0.4
                return 0
            },
            set: { id, value in
                setCalls.append((id, value))
                return 0
            }
        )
        let controller = NativeDisplayController(brightness: services, mainDisplayID: { 42 })

        guard case let .success(applied) = controller.setBrightness(0.8) else {
            return XCTFail("setBrightness 应成功")
        }
        XCTAssertEqual(applied, 0.8, accuracy: 0.0001)
        XCTAssertEqual(setCalls.map(\.0), [42])
        XCTAssertEqual(setCalls.map(\.1), [0.8])

        guard case let .success(adjusted) = controller.adjustBrightness(by: 0.1) else {
            return XCTFail("adjustBrightness 应成功")
        }
        // 读取 0.4（携带主显示器 ID）+ 0.1 后写回 0.5。
        XCTAssertEqual(getIDs, [42])
        XCTAssertEqual(adjusted, 0.5, accuracy: 0.0001)
        XCTAssertEqual(setCalls.last?.0, 42)
        XCTAssertEqual(setCalls.last?.1 ?? -1, 0.5, accuracy: 0.0001)
    }

    func testBrightnessFailureSurfacesStatusCode() {
        let services = NativeDisplayController.BrightnessServices(
            get: { _, _ in -1 },
            set: { _, _ in -1 }
        )
        let controller = NativeDisplayController(brightness: services, mainDisplayID: { 42 })

        guard case let .failure(error) = controller.setBrightness(0.5) else {
            return XCTFail("绑定失败时应返回错误")
        }
        XCTAssertEqual(error.message, "设置亮度失败: DisplayServices(-1)")

        guard case let .failure(readError) = controller.adjustBrightness(by: 0.1) else {
            return XCTFail("读取失败时应返回错误")
        }
        XCTAssertEqual(readError.message, "读取亮度失败: DisplayServices(-1)")
    }

    func testScreenshotPathsDifferWithinSameInstant() {
        let instant = Date(timeIntervalSince1970: 1_700_000_000)

        let first = NativeDisplayController.makeScreenshotPath(directory: "/tmp/shots", date: instant)
        let second = NativeDisplayController.makeScreenshotPath(directory: "/tmp/shots", date: instant)

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.hasPrefix("/tmp/shots/screenshot-1700000000000-"), first)
        XCTAssertTrue(first.hasSuffix(".png"), first)
    }
}

final class NativeAppControllerTests: XCTestCase {
    func testNestedUtilityAppResolvesViaRecursiveSearch() throws {
        let root = try makeSearchRoot()
        let terminal = root.appendingPathComponent("Utilities/Terminal.app")
        try FileManager.default.createDirectory(at: terminal, withIntermediateDirectories: true)

        let found = NativeAppController.findApp(named: "Terminal", searchRoots: [root.path])

        XCTAssertTrue(found?.path.hasSuffix("Utilities/Terminal.app") == true, "\(String(describing: found))")
    }

    func testRecursiveSearchSkipsHiddenAndPackageDescendants() throws {
        let root = try makeSearchRoot()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".hidden/Ghost.app"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Wrapper.app/Contents/Inner.app"),
            withIntermediateDirectories: true
        )

        XCTAssertNil(NativeAppController.findApp(named: "Ghost", searchRoots: [root.path]))
        XCTAssertNil(NativeAppController.findApp(named: "Inner", searchRoots: [root.path]))
        // .app 包本身仍作为条目命中（只是不下钻包内部）。
        XCTAssertTrue(
            NativeAppController.findApp(named: "Wrapper", searchRoots: [root.path])?.path
                .hasSuffix("Wrapper.app") == true
        )
    }

    func testOpenPrefersBundleIDMatch() throws {
        let root = try makeSearchRoot()
        let expected = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        var openedURL: URL?
        let controller = NativeAppController(
            bundleIDResolver: { $0 == "com.apple.Terminal" ? expected : nil },
            searchRoots: [root.path],
            opener: { url, completion in
                openedURL = url
                completion(nil)
            }
        )

        let result = controller.openApplication(named: "com.apple.Terminal")

        guard case .success = result else {
            return XCTFail("bundle id 命中且打开回调成功时应成功: \(result)")
        }
        XCTAssertEqual(openedURL, expected)
    }

    func testOpenFallsBackToRecursiveSearchByName() throws {
        let root = try makeSearchRoot()
        let terminal = root.appendingPathComponent("Utilities/Terminal.app")
        try FileManager.default.createDirectory(at: terminal, withIntermediateDirectories: true)
        var openedURL: URL?
        let controller = NativeAppController(
            bundleIDResolver: { _ in nil },
            searchRoots: [root.path],
            opener: { url, completion in
                openedURL = url
                completion(nil)
            }
        )

        let result = controller.openApplication(named: "terminal")

        guard case .success = result else {
            return XCTFail("目录递归搜索命中且打开回调成功时应成功: \(result)")
        }
        XCTAssertTrue(openedURL?.path.hasSuffix("Utilities/Terminal.app") == true, "\(String(describing: openedURL))")
    }

    func testOpenPropagatesCallbackError() {
        let controller = NativeAppController(
            bundleIDResolver: { _ in URL(fileURLWithPath: "/Applications/Dummy.app") },
            searchRoots: [],
            opener: { _, completion in
                completion(NSError(
                    domain: "NativeAppControllerTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "launch denied"]
                ))
            }
        )

        let result = controller.openApplication(named: "com.dummy")

        guard case let .failure(error) = result else {
            return XCTFail("打开回调报错时应失败: \(result)")
        }
        XCTAssertEqual(error.message, "打开应用失败: launch denied")
    }

    func testOpenTimeoutFailsInsteadOfFakeSuccess() {
        let controller = NativeAppController(
            bundleIDResolver: { _ in URL(fileURLWithPath: "/Applications/Dummy.app") },
            searchRoots: [],
            openTimeout: 0.05,
            opener: { _, _ in
                // 永不回调，模拟 NSWorkspace 挂起。
            }
        )

        let result = controller.openApplication(named: "com.dummy")

        guard case let .failure(error) = result else {
            return XCTFail("打开超时必须失败，不能返回假成功: \(result)")
        }
        XCTAssertTrue(error.message.hasPrefix("打开应用超时"), error.message)
    }

    func testOpenUnknownAppFailsWithoutCallingOpener() {
        var openerCalled = false
        let controller = NativeAppController(
            bundleIDResolver: { _ in nil },
            searchRoots: [],
            opener: { _, completion in
                openerCalled = true
                completion(nil)
            }
        )

        let result = controller.openApplication(named: "NoSuchApp")

        guard case let .failure(error) = result else {
            return XCTFail("找不到应用时应失败: \(result)")
        }
        XCTAssertEqual(error.message, "找不到应用: NoSuchApp")
        XCTAssertFalse(openerCalled)
    }

    // MARK: - 运行中应用匹配（本地化免疫）

    /// 中文系统下运行中的 Calculator localizedName 是「计算器」，远程指令传英文名；
    /// 走名称→包→bundle id 解析链路后按 bid 匹配必须命中。
    func testRunningAppMatchesViaResolvedBundleIDDespiteLocalizedName() {
        XCTAssertTrue(
            NativeAppController.matchesRunningApp(
                localizedName: "计算器",
                bundleIdentifier: "com.apple.calculator",
                needle: "Calculator",
                resolvedBundleID: "com.apple.calculator"
            )
        )
    }

    func testRunningAppMatchesViaLiteralBundleIDNeedle() {
        XCTAssertTrue(
            NativeAppController.matchesRunningApp(
                localizedName: "计算器",
                bundleIdentifier: "com.apple.calculator",
                needle: "com.apple.CALCULATOR",
                resolvedBundleID: nil
            )
        )
    }

    func testRunningAppMatchesViaLocalizedNameFallback() {
        XCTAssertTrue(
            NativeAppController.matchesRunningApp(
                localizedName: "计算器",
                bundleIdentifier: "com.apple.calculator",
                needle: "计算器",
                resolvedBundleID: nil
            )
        )
    }

    func testRunningAppRejectsUnrelatedApp() {
        XCTAssertFalse(
            NativeAppController.matchesRunningApp(
                localizedName: "Safari浏览器",
                bundleIdentifier: "com.apple.Safari",
                needle: "Calculator",
                resolvedBundleID: "com.apple.calculator"
            )
        )
    }

    private func makeSearchRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cicada-appsearch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }
}

/// 截图内联回传：JPEG base64 编码与尺寸上限降级。
final class ScreenshotInlineTests: XCTestCase {
    private func writePNG(width: Int, height: Int, noise: Bool) throws -> String {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let pixels = rep.bitmapData else {
            throw NSError(domain: "ScreenshotInlineTests", code: 1)
        }
        for i in 0 ..< (rep.bytesPerRow * height) {
            pixels[i] = noise ? UInt8.random(in: 0 ... 255) : 200
        }
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let path = NSTemporaryDirectory() + "cicada-shot-\(UUID().uuidString).png"
        try png.write(to: URL(fileURLWithPath: path))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return path
    }

    func testSmallScreenshotEncodesToValidJPEGBase64() throws {
        let path = try writePNG(width: 120, height: 80, noise: false)

        let encoded = try XCTUnwrap(MacOSCommandGateway.inlineScreenshotBase64(path: path))
        let data = try XCTUnwrap(Data(base64Encoded: encoded), "必须是合法 base64")
        XCTAssertNotNil(NSBitmapImageRep(data: data), "必须能按 JPEG 解码")
    }

    /// 噪声图是 JPEG 最坏情况：也必须压到上限以内。
    func testNoisyScreenshotStaysUnderInlineLimit() throws {
        let path = try writePNG(width: 1600, height: 1200, noise: true)

        let encoded = try XCTUnwrap(MacOSCommandGateway.inlineScreenshotBase64(path: path))
        XCTAssertLessThanOrEqual(
            encoded.utf8.count,
            MacOSCommandGateway.screenshotInlineMaxBase64Bytes
        )
    }

    func testUnreadableFileReturnsNil() {
        XCTAssertNil(MacOSCommandGateway.inlineScreenshotBase64(path: "/nonexistent/x.png"))
    }
}

final class NativeBluetoothControllerTests: XCTestCase {
    /// 未授权时必须直接失败，不得触碰 IOBluetooth——裸 Mach-O 在 macOS 15 上调用
    /// IOBluetooth 会被 TCC 以缺 NSBluetoothAlwaysUsageDescription 为由 SIGABRT。
    func testPowerStateFailsWithoutAuthorization() {
        let controller = NativeBluetoothController(authorizationState: { .notAllowed })

        guard case let .failure(error) = controller.powerState() else {
            return XCTFail("未授权时应失败")
        }
        XCTAssertTrue(error.message.contains("蓝牙权限"), "\(error.message)")
    }

    func testSetPowerStateFailsWithoutAuthorization() {
        let controller = NativeBluetoothController(authorizationState: { .notAllowed })

        guard case let .failure(error) = controller.setPowerState(true) else {
            return XCTFail("未授权时应失败")
        }
        XCTAssertTrue(error.message.contains("蓝牙权限"), "\(error.message)")
    }
}
