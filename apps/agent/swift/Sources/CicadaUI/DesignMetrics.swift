import SwiftUI

/// 集中定义间距、圆角、阴影等设计常量，避免散落魔数。
/// 按 Design.md §2.3 原样实现。
enum DesignMetrics {
    /// 8pt 网格间距。
    enum Spacing {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 20
        static let s6: CGFloat = 24
        static let s8: CGFloat = 32
        static let s10: CGFloat = 40
        static let s12: CGFloat = 48
    }

    /// 圆角半径。
    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
        static let x2l: CGFloat = 28
    }

    /// 阴影参数（radius, x, y, opacity）。
    enum Shadow {
        static let sm = (radius: CGFloat(2), x: CGFloat(0), y: CGFloat(1), opacity: Double(0.3))
        static let md = (radius: CGFloat(12), x: CGFloat(0), y: CGFloat(4), opacity: Double(0.25))
        static let lg = (radius: CGFloat(32), x: CGFloat(0), y: CGFloat(12), opacity: Double(0.35))
        /// 弥散阴影，卡片浮起。
        static let diff = (radius: CGFloat(20), x: CGFloat(0), y: CGFloat(2), opacity: Double(0.15))
        /// 彩色 accent 阴影。
        static let accent = (radius: CGFloat(20), x: CGFloat(0), y: CGFloat(0), opacity: Double(0.15), color: Color.cicadaAccent)
    }

    /// 侧栏宽度。
    static let sidebarWidth: CGFloat = 240
    /// 进度环尺寸。
    static let progressRingSize: CGFloat = 56
}