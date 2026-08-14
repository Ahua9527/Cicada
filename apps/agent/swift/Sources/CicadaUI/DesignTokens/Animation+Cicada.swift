import SwiftUI

/// 动效 token(对齐 Design.md §10)。新代码引用此处,不在调用点手写数值;
/// 存量站点随改动逐步收敛,不做大爆炸重写。
enum CicadaMotion {
    /// hover 缩放 spring(NotchMenu / FolderGrid 等)。
    static let hoverSpring = Animation.spring(response: 0.2)
    /// hover 缩放幅度(统一;原 NotchMenu 1.05 与 FolderGrid 1.02 并存)。
    static let hoverScale: CGFloat = 1.02
    /// hover 缩放的纯函数判断：开启「减弱动态效果」时恒为 1（只保留颜色变化，
    /// 不做缩放/弹簧动画）；普通模式 hover 时放大、离开时归 1。
    static func hoverScale(isHovering: Bool, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 1 }
        return isHovering ? hoverScale : 1
    }
    /// 侧栏选中跟随(Design.md §10: easeInOut 0.15)。
    static let selection = Animation.easeInOut(duration: 0.15)
    /// 输入框焦点边框/光晕(进场用 ease-out)。
    static let focusGlow = Animation.easeOut(duration: 0.15)
}
