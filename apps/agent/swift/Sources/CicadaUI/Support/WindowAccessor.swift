import AppKit
import SwiftUI

/// `NSViewRepresentable` 用于获取 NSWindow 并在闭包中配置其层级等属性。
///
/// ⚠️ 这是 CicadaUI 内唯一允许 `import AppKit` 的文件（窗口配置例外）。
/// 其他文件不得 import AppKit/Cocoa。仅用于设层级，不承载视图内容。
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        onWindow(nsView.window)
    }
}