import Foundation

/// NotchDrop 引擎委托协议，供 Xcode 宿主实现。
///
/// CicadaUI 的 `NotchPanel`/`NotchMenu`/`NotchSection` 通过此协议调用宿主引擎
/// （TrayDrop 落盘 / AirDrop / 面板控制 / 外链），不直接引用 `TrayDrop`/`AirDrop`/
/// `NotchViewModel` 等宿主类型。
///
/// 宿主实现：`extension NotchViewModel: NotchDropDelegate { ... }`
/// （`NotchViewModel` 已是 `ObservableObject`，仅需补齐方法实现）。
///
/// 协议方法只读不写状态——本轮 `NotchPanel`/`NotchMenu` 不读宿主暂存项列表/加载计数，
/// 只调操作，故协议最小（8 方法）。未来若需读状态可扩展协议不破坏实现。
/// 参数类型限于 `[NSItemProvider]`/`[URL]`（Foundation），不泄漏宿主 `TrayDrop`/`DropItem`/`AirDrop` 类型。
public protocol NotchDropDelegate: AnyObject, ObservableObject {

    // MARK: - TrayDrop 暂存引擎

    /// 接收拖放数据并落盘到暂存目录。
    /// 宿主实现：`DispatchQueue.global().async { TrayDrop.shared.load(providers) }`。
    func loadTray(providers: [NSItemProvider])

    /// 清空全部暂存文件。
    /// 宿主实现：`TrayDrop.shared.removeAll(); notchClose()`。
    func clearTray()

    // MARK: - AirDrop 引擎

    /// 拖放直传：由拖放区 `.onDrop` 触发，宿主做 providers→urls→AirDrop。
    /// 宿主实现：`guard let urls = providers.interfaceConvert() else { return }; AirDrop(files: urls).begin()`。
    func airDrop(providers: [NSItemProvider])

    /// 文件选择器选中：由 AirDrop 按钮点击弹 `NSOpenPanel` 后触发。
    /// 宿主实现：`AirDrop(files: urls).begin()`。
    func airDrop(urls: [URL])

    /// 弹出 `NSOpenPanel` 选文件，选中后调 `airDrop(urls:)`。
    /// 宿主实现：弹 `NSOpenPanel` → `airDrop(urls: picker.urls)`。
    func openTrayPicker()

    // MARK: - 面板控制

    /// 关闭刘海面板。宿主实现：`notchClose()`。
    func close()

    /// 打开设置页。宿主实现：`showSettings()`（路由到控制中心设置 Tab）。
    func showSettings()

    // MARK: - 外链

    /// 打开 GitHub 项目页。宿主实现：`NSWorkspace.shared.open(productPage); notchClose()`。
    func openGitHub()

    /// 打开赞助页。宿主实现：`NSWorkspace.shared.open(sponsorPage); notchClose()`。
    func openSponsor()
}

// MARK: - 预览/单测用 Mock

/// 预览与单测用的 `NotchDropDelegate` 空实现，记录各方法调用计数。
///
/// 供 `#Preview` 与 `CicadaUITests` 共用——所有方法空实现仅自增计数器，
/// 便于断言协议可被 conform 且转发正确。
///
/// 不标 `@MainActor`：协议 `NotchDropDelegate` 本身是非隔离的（宿主 `NotchViewModel`
/// 是 `NSObject` + `ObservableObject`，其方法非 MainActor 隔离），Mock 自增计数器
/// 也无需线程隔离。若加 `@MainActor` 会让方法无法 satisfy 协议的非隔离要求（Swift 6 报错）。
final class NotchDropDelegatePreviewMock: ObservableObject, NotchDropDelegate {
    var loadTrayCallCount = 0
    var clearTrayCallCount = 0
    var airDropProvidersCallCount = 0
    var airDropUrlsCallCount = 0
    var openTrayPickerCallCount = 0
    var closeCallCount = 0
    var showSettingsCallCount = 0
    var openGitHubCallCount = 0
    var openSponsorCallCount = 0

    func loadTray(providers: [NSItemProvider]) { loadTrayCallCount += 1 }
    func clearTray() { clearTrayCallCount += 1 }
    func airDrop(providers: [NSItemProvider]) { airDropProvidersCallCount += 1 }
    func airDrop(urls: [URL]) { airDropUrlsCallCount += 1 }
    func openTrayPicker() { openTrayPickerCallCount += 1 }
    func close() { closeCallCount += 1 }
    func showSettings() { showSettingsCallCount += 1 }
    func openGitHub() { openGitHubCallCount += 1 }
    func openSponsor() { openSponsorCallCount += 1 }
}
