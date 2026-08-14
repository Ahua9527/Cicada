import SwiftUI

/// 刘海面板菜单态（`contentType == .menu` 的内容）——横向 6 方块按钮。
///
/// 6 个按钮：退出 / AirDrop / GitHub / 赞助 / 设置 / 清空。
/// 「退出」真正退出整个 App（长按确认，防误退导致安防失效），不是只关面板。
///
/// 纯 SwiftUI，可 `swift build` 验证。
/// 宿主 `NotchContentView` 在 `.menu` 分支用 `NotchMenu(delegate: vm)`。
/// 背景毛玻璃 + 圆角 + 阴影由宿主 `NotchView` 外壳提供，本视图不自带背景。
///
/// 对照 Design.md §6.2 `NotchMenu`。注：Design.md §6.2 文字写「5 方块」但列了 6 个按钮，
/// 文字「5」是笔误，本实现按 6 个落地（与现有 `NotchMenuView.swift` 一致）。
public struct NotchMenu<Delegate: ObservableObject & NotchDropDelegate>: View {
    /// 引擎委托，通过 `@ObservedObject` 观察宿主 `NotchViewModel`。
    @ObservedObject private var delegate: Delegate

    /// 内部间距。
    private let spacing: CGFloat
    /// 方块圆角半径。
    private let cornerRadius: CGFloat

    public init(delegate: Delegate, spacing: CGFloat = 12, cornerRadius: CGFloat = 16) {
        self.delegate = delegate
        self.spacing = spacing
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        HStack(spacing: spacing) {
            menuButton(
                icon: "power",
                label: String(localized: "退出", bundle: .module),
                tint: .cicadaDanger,
                requiresHoldConfirmation: true
            ) {
                delegate.quitApp()
            }
            menuButton(icon: "airplayaudio", label: "AirDrop", tint: .cicadaAccent) {
                // 点 AirDrop 弹文件选择器（NSOpenPanel），选中后 airDrop(urls:)。
                delegate.openTrayPicker()
            }
            menuButton(icon: "ellipsis.bubble", label: "GitHub", tint: .cicadaAccent) {
                delegate.openGitHub()
            }
            menuButton(icon: "heart.fill", label: String(localized: "赞助", bundle: .module), tint: .cicadaAccent) {
                delegate.openSponsor()
            }
            menuButton(icon: "gearshape", label: String(localized: "设置", bundle: .module), tint: .cicadaAccent) {
                delegate.showSettings()
            }
            menuButton(
                icon: "trash",
                label: String(localized: "清空", bundle: .module),
                tint: .cicadaDanger,
                requiresHoldConfirmation: true
            ) {
                delegate.clearTray()
            }
        }
        .padding(spacing)
        .preferredColorScheme(.dark)
    }

    /// 单个方块按钮。
    ///
    /// 对照 Design.md §6.2 `NotchMenuButton`：72×72 圆角方块，hover 缩放 1.05 + 背景提亮。
    /// 本实现用中性 tint 软背景 + tint 边框（不依赖 `ColorfulView` 装饰，符合方案 B 精神）。
    @ViewBuilder
    private func menuButton(
        icon: String,
        label: String,
        tint: Color,
        requiresHoldConfirmation: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if requiresHoldConfirmation {
            HoldToConfirmButton(tint: tint, cornerRadius: cornerRadius, action: action) {
                MenuButtonContent(icon: icon, label: label, tint: tint, cornerRadius: cornerRadius)
            }
        } else {
            Button(action: action) {
                MenuButtonContent(icon: icon, label: label, tint: tint, cornerRadius: cornerRadius)
            }
            .buttonStyle(.plain)
        }
    }
}

/// 菜单方块按钮内容（独立以承载 hover 缩放）。
private struct MenuButtonContent: View {
    let icon: String
    let label: String
    let tint: Color
    let cornerRadius: CGFloat

    @State private var hover = false

    var body: some View {
        VStack(spacing: DesignMetrics.Spacing.s2) {
            Image(systemName: icon)
                .font(.title3)
            Text(label)
                .font(.caption)
        }
        .frame(width: 72, height: 72)
        .background(tint.opacity(hover ? 0.2 : 0.12))
        .foregroundStyle(tint)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(tint.opacity(0.3), lineWidth: 1)
        )
        .scaleEffect(hover ? CicadaMotion.hoverScale : 1)
        .animation(CicadaMotion.hoverSpring, value: hover)
        .onHover { hover = $0 }
    }
}

#Preview {
    NotchMenu(delegate: NotchDropDelegatePreviewMock())
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .overlay(
            RoundedRectangle(cornerRadius: 32).stroke(.white.opacity(0.06), lineWidth: 1)
        )
}
