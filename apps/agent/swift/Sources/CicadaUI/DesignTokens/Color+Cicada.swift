import SwiftUI

/// `Color.cicadaXxx` 扩展，从 CicadaUI 模块 bundle 加载 Color Set。
///
/// 使用 `ShapeStyle where Self == Color` 约束，使 `.cicadaXxx` 可在所有接受
/// `Color` 或 `ShapeStyle` 的上下文中以 leading-dot 语法使用：
/// `.foregroundStyle(.cicadaAccent)` / `.background(.cicadaBgSurface)` /
/// `.fill(.cicadaBorderSubtle)` / `.stroke(.cicadaAccent)` 等。
///
/// ⚠️ 必须使用 `bundle: .module`，否则 SwiftPM library 内 `Color("Accent")`
/// 找不到资源 bundle，运行时返回默认色（透明/黑）。
extension ShapeStyle where Self == Color {
    static var cicadaAccent: Color { Color("Accent", bundle: .module) }
    static var cicadaAccentHover: Color { Color("AccentHover", bundle: .module) }
    static var cicadaBgBase: Color { Color("BGBase", bundle: .module) }
    static var cicadaBgSurface: Color { Color("BGSurface", bundle: .module) }
    static var cicadaBgSurface2: Color { Color("BGSurface2", bundle: .module) }
    static var cicadaBGElevated: Color { Color("BGElevated", bundle: .module) }
    static var cicadaBgHover: Color { Color("BGHover", bundle: .module) }
    static var cicadaBorderSubtle: Color { Color("BorderSubtle", bundle: .module) }
    static var cicadaBorder: Color { Color("BorderDefault", bundle: .module) }
    static var cicadaBorderStrong: Color { Color("BorderStrong", bundle: .module) }
    static var cicadaTextPrimary: Color { Color("TextPrimary", bundle: .module) }
    static var cicadaTextSecondary: Color { Color("TextSecondary", bundle: .module) }
    static var cicadaTextTertiary: Color { Color("TextTertiary", bundle: .module) }
    static var cicadaTextInverse: Color { Color("TextInverse", bundle: .module) }
    static var cicadaWarn: Color { Color("Warn", bundle: .module) }
    static var cicadaDanger: Color { Color("Danger", bundle: .module) }
    static var cicadaInfo: Color { Color("Info", bundle: .module) }
    static var cicadaPurple: Color { Color("Purple", bundle: .module) }

    // AlarmSunset1/2/3 不建扩展（ColorfulView 自带 .sunset，不需要）
}