import SwiftUI

/// 维护页 3 列网格按钮容器。
struct FolderGridButton: View {
    let actions: [FolderAction]

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: DesignMetrics.Spacing.s3) {
            ForEach(actions) { action in
                FolderButton(action: action)
            }
        }
    }
}

/// 单个文件夹操作按钮。
struct FolderButton: View {
    let action: FolderAction
    @State private var hover = false
    @State private var hoverScale = false

    var body: some View {
        Group {
            if action.requiresHoldConfirmation {
                HoldToConfirmButton(
                    tint: .cicadaDanger,
                    cornerRadius: DesignMetrics.Radius.md,
                    action: action.action
                ) {
                    content
                }
            } else {
                Button(action: action.action) {
                    content
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { isHovering in
            hover = isHovering
            withAnimation(CicadaMotion.hoverSpring) {
                hoverScale = isHovering
            }
        }
    }

    private var content: some View {
        VStack(spacing: DesignMetrics.Spacing.s2) {
            Image(systemName: action.systemImage)
                .font(.title3)
                .foregroundStyle(action.isDanger ? .cicadaDanger : .cicadaTextPrimary)
            Text(action.label)
                .font(.caption)
                .foregroundStyle(.cicadaTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignMetrics.Spacing.s4)
        .background(hover ? Color.cicadaAccent.opacity(0.12) : Color.cicadaBgBase)
        .overlay(
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                .stroke(
                    hover ? AnyShapeStyle(.cicadaAccent.opacity(0.3)) : AnyShapeStyle(.cicadaBorderSubtle),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
        .scaleEffect(hoverScale ? CicadaMotion.hoverScale : 1)
    }
}

#Preview {
    FolderGridButton(actions: [
        FolderAction(systemImage: "trash", label: "清空缓存", isDanger: false, action: {}),
        FolderAction(systemImage: "arrow.triangle.2.circlepath", label: "重启服务", isDanger: false, action: {}),
        FolderAction(systemImage: "doc.on.doc", label: "导出日志", isDanger: false, action: {}),
        FolderAction(systemImage: "exclamationmark.triangle", label: "重置配置", isDanger: true, action: {}),
        FolderAction(systemImage: "magnifyingglass", label: "诊断", isDanger: false, action: {}),
        FolderAction(systemImage: "xmark.octagon", label: "强制停止", isDanger: true, action: {}),
    ])
    .padding()
    .background(.cicadaBgSurface)
    .frame(width: 400)
}
