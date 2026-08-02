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

    public init(delegate: Delegate, cornerRadius: CGFloat = 16, spacing: CGFloat = 16) {
        self.delegate = delegate
        self.cornerRadius = cornerRadius
        self.spacing = spacing
    }

    public var body: some View {
        VStack(spacing: spacing) {
            notchHeader
            HStack(spacing: spacing) {
                NotchSection(
                    delegate: delegate,
                    icon: "airplayaudio",
                    text: "拖放以 AirDrop",
                    kind: .airDrop,
                    cornerRadius: cornerRadius
                )
                NotchSection(
                    delegate: delegate,
                    icon: "tray.and.arrow.down.fill",
                    text: "拖放文件到此处暂存一周",
                    kind: .tray,
                    cornerRadius: cornerRadius
                )
            }
        }
        .padding(spacing)
        .frame(maxWidth: 600, maxHeight: 160)   // 对照 NotchViewModel.notchOpenedSize 600×160
        .preferredColorScheme(.dark)
    }

    /// 标题行（对照 NotchHeaderView：标题 + ellipsis）。
    ///
    /// ellipsis 点击切菜单是宿主 `NotchViewModel.cycleInteractiveContent()`，由宿主
    /// `NotchViewModel+Events` 的点击事件处理（现有逻辑：点 headline 区触发
    /// `cycleInteractiveContent()`）。本轮协议不补 `cycleMenu()`，保持最小；
    /// 此处 ellipsis **纯装饰**（不绑动作）。若需在 CicadaUI 内点击切菜单，
    /// 可协议补 `func cycleMenu()`，但不推荐（增加协议面）。
    private var notchHeader: some View {
        HStack {
            Text("NotchDrop")
                .font(.system(.headline, design: .rounded))
            Spacer()
            Image(systemName: "ellipsis")
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
