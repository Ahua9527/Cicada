import ApplicationServices
import Foundation

final class NativeLockController: NativeLockControlling {
    func lockScreen() -> Result<Void, NativeCommandError> {
        guard isAccessibilityTrusted() else {
            return .failure(.message("锁屏需要辅助功能权限，请在系统设置中允许 Cicada 控制这台 Mac"))
        }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: false) else {
            return .failure(.message("无法创建锁屏快捷键事件"))
        }

        let flags: CGEventFlags = [.maskCommand, .maskControl]
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return .success(())
    }

    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }
}
