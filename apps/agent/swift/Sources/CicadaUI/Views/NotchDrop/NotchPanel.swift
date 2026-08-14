import SwiftUI

/// 刘海面板打开态（`contentType == .normal` 的内容）。
///
/// 布局：`NotchHeader`（标题 + ellipsis）+ `HStack(两个 NotchSection 拖放区)`。
///
/// 纯 SwiftUI，可 `swift build` 验证。
/// 宿主 `NotchContentView` 在 `.normal` 分支用 `NotchPanel(delegate: vm)`。
/// 背景毛玻璃 + 圆角 + 阴影由宿主 `NotchView` 外壳提供，本视图不自带背景。
///
/// 对照 Design.md §6.1 `NotchPanel`。
public struct NotchPanel<Delegate: ObservableObject & NotchDropDelegate>: View {
    /// 引擎委托，通过 `@ObservedObject` 观察宿主 `NotchViewModel`。
    @ObservedObject private var delegate: Delegate

    /// 圆角半径，沿用宿主 `NotchViewModel.cornerRadius`（默认 16）。
    /// 由宿主传入，使本视图圆角与宿主窗口形状一致。
    private let cornerRadius: CGFloat
    /// 内部间距，对齐 `NotchViewModel.spacing`。
    private let spacing: CGFloat
    /// 宿主显式注入的菜单切换动作。
    private let onShowMenu: () -> Void

    /// 菜单按钮(⋯)悬停态:放大热区后的 hover 反馈。
    @State private var menuHover = false

    /// 宿主注入的暂存区内容（既有 `TrayView`，覆盖空态 + 已暂存文件列表）。
    /// `nil` 时用库内空态拖放区（NotchSection .tray），保持库独立可预览。
    @Environment(\.trayContent) private var trayContent

    public init(
        delegate: Delegate,
        cornerRadius: CGFloat = 16,
        spacing: CGFloat = 16,
        onShowMenu: @escaping () -> Void = {}
    ) {
        self.delegate = delegate
        self.cornerRadius = cornerRadius
        self.spacing = spacing
        self.onShowMenu = onShowMenu
    }

    public var body: some View {
        VStack(spacing: spacing) {
            notchHeader
            HStack(spacing: spacing) {
                NotchSection(
                    delegate: delegate,
                    icon: "airplayaudio",
                    text: String(localized: "拖放以 AirDrop", bundle: .module),
                    kind: .airDrop,
                    cornerRadius: cornerRadius
                )
                traySlot
            }
        }
        .padding(spacing)
        .frame(maxWidth: 600, maxHeight: 160)   // 对照 NotchViewModel.notchOpenedSize 600×160
        .preferredColorScheme(.dark)
    }

    /// 暂存区槽位：宿主注入时用其视图（含已暂存文件的打开/拖拽/删除），
    /// 否则回退到库内空态拖放区。
    @ViewBuilder
    private var traySlot: some View {
        if let trayContent {
            trayContent()
        } else {
            NotchSection(
                delegate: delegate,
                icon: "tray.and.arrow.down.fill",
                text: String(localized: "拖放文件到此处暂存一周", bundle: .module),
                kind: .tray,
                cornerRadius: cornerRadius
            )
        }
    }

    /// 标题行(对照 NotchHeaderView:标题 + ellipsis)。
    ///
    /// 菜单动作由宿主显式注入,避免用不可聚焦的全局标题区域接管点击。
    /// ⋯ 热区扩到 28×28(原热区只有省略号字形本身,约 17×5,太难点中)。
    private var notchHeader: some View {
        HStack {
            Text("NotchDrop")
                .font(.system(.headline, design: .rounded))
            Spacer()
            Button(action: onShowMenu) {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
                    .background(menuHover ? Color.white.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.sm))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { menuHover = $0 }
            .animation(.easeOut(duration: 0.1), value: menuHover)
            .accessibilityLabel(String(localized: "菜单", bundle: .module))
        }
    }
}

#Preview {
    NotchPanel(delegate: NotchDropDelegatePreviewMock())
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .overlay(
            RoundedRectangle(cornerRadius: 32).stroke(.white.opacity(0.06), lineWidth: 1)
        )
}
