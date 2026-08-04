import SwiftUI

/// Primary 按钮样式：accent 背景，inverse 文字。
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, DesignMetrics.Spacing.s4)
            .padding(.vertical, DesignMetrics.Spacing.s2)
            .background(configuration.isPressed ? Color.cicadaAccentHover : Color.cicadaAccent)
            .foregroundStyle(.cicadaTextInverse)
            .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Ghost 按钮样式：elevated 背景，secondary 文字，default 边框。
///
/// ⚠️ 修复 Design.md §4.7 typo `.cicadaTextSecondaryondary` → `.cicadaTextSecondary`。
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, DesignMetrics.Spacing.s4)
            .padding(.vertical, DesignMetrics.Spacing.s2)
            .background(configuration.isPressed ? Color.cicadaBgHover : Color.cicadaBGElevated)
            .foregroundStyle(.cicadaTextSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                    .stroke(.cicadaBorder, lineWidth: 1)
            )
    }
}

/// Danger 按钮样式：danger 软背景，danger 文字，danger 软边框。
struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, DesignMetrics.Spacing.s4)
            .padding(.vertical, DesignMetrics.Spacing.s2)
            .background(Color.cicadaDanger.opacity(configuration.isPressed ? 0.2 : 0.12))
            .foregroundStyle(.cicadaDanger)
            .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                    .stroke(.cicadaDanger.opacity(0.3), lineWidth: 1)
            )
    }
}

/// Small 按钮样式：小尺寸 accent 按钮。
struct SmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, DesignMetrics.Spacing.s3)
            .padding(.vertical, DesignMetrics.Spacing.s1)
            .background(configuration.isPressed ? Color.cicadaAccentHover : Color.cicadaAccent)
            .foregroundStyle(.cicadaTextInverse)
            .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.sm))
    }
}

#Preview {
    VStack(spacing: 12) {
        Button("Primary") {}
            .buttonStyle(PrimaryButtonStyle())
        Button("Ghost") {}
            .buttonStyle(GhostButtonStyle())
        Button("Danger") {}
            .buttonStyle(DangerButtonStyle())
        Button("Small") {}
            .buttonStyle(SmallButtonStyle())
    }
    .padding()
    .background(.cicadaBgSurface)
    .frame(width: 200)
}