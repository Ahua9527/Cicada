import SwiftUI

/// 概览 Hero 卡片（渐变背景 + 状态图标 + 标题 + 徽章）。
struct StatusHeroCard: View {
    let state: SentinelState

    var body: some View {
        HStack(spacing: DesignMetrics.Spacing.s5) {
            StatusIcon(state: state, size: 56)
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
                HStack(spacing: DesignMetrics.Spacing.s3) {
                    Text(state.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.cicadaTextPrimary)
                    StatusBadge(state: state)
                }
                Text(state.description)
                    .font(.subheadline)
                    .foregroundStyle(.cicadaTextSecondary)
            }
            Spacer()
        }
        .padding(DesignMetrics.Spacing.s6)
        .background {
            ZStack {
                LinearGradient(
                    colors: [.cicadaBgSurface2, .cicadaAccent.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [.cicadaAccent.opacity(0.12), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 200
                )
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.xl)
                .stroke(.cicadaBorderSubtle, lineWidth: 1)
        )
    }
}

/// 状态图标（SF Symbol + 状态色圆背景）。
struct StatusIcon: View {
    let state: SentinelState
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(state.badgeColor.opacity(0.15))
                .frame(width: size, height: size)
            Image(systemName: state.systemImage)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(state.badgeColor)
        }
        .frame(width: size, height: size)
    }
}

/// 状态徽章（capsule + 状态色）。
struct StatusBadge: View {
    let state: SentinelState

    var body: some View {
        Text(state.title)
            .font(.caption.weight(.medium))
            .foregroundStyle(state.badgeColor)
            .padding(.horizontal, DesignMetrics.Spacing.s3)
            .padding(.vertical, DesignMetrics.Spacing.s1)
            .background(state.badgeColor.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(state.badgeColor.opacity(0.3), lineWidth: 1))
    }
}

#Preview {
    VStack(spacing: 16) {
        StatusHeroCard(state: .running)
        StatusHeroCard(state: .warning)
        StatusHeroCard(state: .idle)
    }
    .padding()
    .background(.cicadaBgSurface)
    .frame(width: 500)
}