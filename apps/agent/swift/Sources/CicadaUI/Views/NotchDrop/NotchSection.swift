import SwiftUI
import UniformTypeIdentifiers

/// 单个刘海拖放区。
///
/// 本轮只实现**空态**（拖放提示 + 虚线边框 + `.onDrop` 视觉反馈 + 转发落盘）。
/// 非空态（DropItemView 横滑列表）涉及 QuickLook/NSImage 预览，留 Xcode 宿主 P4 扩展。
///
/// 对照 Design.md §6.1 `NotchSection`（dashed 拖放区）。
struct NotchSection<Delegate: ObservableObject & NotchDropDelegate>: View {
    /// 引擎委托，通过 `@ObservedObject` 观察宿主 `NotchViewModel`。
    @ObservedObject var delegate: Delegate

    /// SF Symbol 图标名。
    let icon: String
    /// 拖放区文字（固定字面量，对照 Design.md §6.1）。
    let text: String
    /// 拖放区类型（决定转发到哪个 delegate 方法）。
    let kind: Kind
    /// 圆角半径（沿用宿主 `vm.cornerRadius`，由 `NotchPanel` 传入）。

    let cornerRadius: CGFloat

    /// 拖放悬停时高亮状态。
    @State private var isTargeted = false

    /// 拖放区类型。
    enum Kind {
        /// AirDrop 区：拖放 → `delegate.airDrop(providers:)`；点击 → `delegate.openTrayPicker()`。
        case airDrop
        /// 暂存区：拖放 → `delegate.loadTray(providers:)`；点击无动作（非空态列表留宿主）。
        case tray
    }

    var body: some View {
        panel
            // 收窄 UTI 为实际支持的 `.fileURL`，避免吞掉任意 pasteboard 类型；
            // providers 为空时拒绝 drop，由调用者据此决定是否接受。
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                guard !providers.isEmpty else { return false }
                handleDrop(providers)
                return true
            }
            .onTapGesture(perform: handleTap)
    }

    // MARK: - 视觉

    private var panel: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(style: StrokeStyle(lineWidth: 4, dash: [10]))
            .foregroundStyle(isTargeted ? Color.cicadaAccent.opacity(0.8) : Color.white.opacity(0.1))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isTargeted ? Color.cicadaAccent.opacity(0.15) : Color.white.opacity(0.08))
            )
            .overlay {
                VStack(spacing: DesignMetrics.Spacing.s2) {
                    Image(systemName: icon)
                        .font(.title3)
                    Text(text)
                        .font(.system(.headline, design: .rounded))
                        .multilineTextAlignment(.center)
                }
                .padding(DesignMetrics.Spacing.s4)
            }
            .aspectRatio(1, contentMode: .fit)   // 对照 AirDropView: aspectRatio(1, .fit)
            .animation(.spring(response: 0.3), value: isTargeted)
    }

    // MARK: - 交互

    private func handleDrop(_ providers: [NSItemProvider]) {
        switch kind {
        case .airDrop:
            // AirDrop 拖放走 providers 入口：宿主做 providers→urls→AirDrop。
            // CicadaUI 不依赖宿主的 `interfaceConvert` 扩展，故暴露 providers 给宿主转换。
            delegate.airDrop(providers: providers)
        case .tray:
            // 暂存区：直接 providers 入口落盘。
            delegate.loadTray(providers: providers)
        }
    }

    private func handleTap() {
        switch kind {
        case .airDrop:
            // 点击 AirDrop 区弹文件选择面板（NSOpenPanel），选中后发起 AirDrop。
            delegate.openTrayPicker()
        case .tray:
            // 暂存区点击无动作（非空态列表交互留宿主 P4）。
            break
        }
    }
}

#Preview {
    HStack(spacing: DesignMetrics.Spacing.s4) {
        NotchSection(
            delegate: NotchDropDelegatePreviewMock(),
            icon: "airplayaudio",
            text: "拖放以 AirDrop",
            kind: .airDrop,
            cornerRadius: 16
        )
        NotchSection(
            delegate: NotchDropDelegatePreviewMock(),
            icon: "tray.and.arrow.down.fill",
            text: "拖放文件到此处暂存一周",
            kind: .tray,
            cornerRadius: 16
        )
    }
    .padding(DesignMetrics.Spacing.s4)
    .frame(maxWidth: 600, maxHeight: 160)
    .background(Color.black.opacity(0.55))
    .clipShape(RoundedRectangle(cornerRadius: 32))
    .overlay(
        RoundedRectangle(cornerRadius: 32).stroke(.white.opacity(0.06), lineWidth: 1)
    )
}