import SwiftUI

/// 就绪度卡片 + ProgressRing + ReadinessRow 列表。
struct ReadinessCard: View {
    let items: [ReadinessItem]
    let progress: Double

    init(items: [ReadinessItem], progress: Double? = nil) {
        self.items = items
        self.progress = progress ?? SnapshotMapper.readinessProgress(items)
    }

    var body: some View {
        HStack(alignment: .top, spacing: DesignMetrics.Spacing.s5) {
            ProgressRing(progress: progress)
                .frame(width: DesignMetrics.progressRingSize, height: DesignMetrics.progressRingSize)

            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
                Text(String(localized: "就绪度", bundle: .module))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cicadaTextSecondary)

                ForEach(items) { item in
                    ReadinessRow(item: item)
                }
            }
            Spacer()
        }
        .padding(DesignMetrics.Spacing.s5)
        .background(.cicadaBgSurface2)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.lg)
                .stroke(.cicadaBorderSubtle, lineWidth: 1)
        )
    }
}

/// 进度环。
struct ProgressRing: View {
    let progress: Double
    let size: CGFloat
    private let lineWidth: CGFloat = 4

    init(progress: Double, size: CGFloat = DesignMetrics.progressRingSize) {
        self.progress = progress
        self.size = size
    }

    var body: some View {
        ZStack {
            Ring(progress: 1)
                .stroke(.cicadaBorderSubtle, lineWidth: lineWidth)
            Ring(progress: progress)
                .stroke(.cicadaAccent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.caption.weight(.bold))
                .foregroundStyle(.cicadaAccent)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.5), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "就绪度", bundle: .module))
        .accessibilityValue("\(Int(progress * 100))%")
    }

    /// 环形 Shape。
    struct Ring: Shape {
        let progress: Double
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.addArc(
                center: CGPoint(x: r.midX, y: r.midY),
                radius: min(r.width, r.height) / 2 - 2,
                startAngle: .zero,
                endAngle: .degrees(360 * progress),
                clockwise: false
            )
            return p
        }
    }
}

/// 就绪度行。
struct ReadinessRow: View {
    let item: ReadinessItem

    private var statusColor: Color {
        switch item.status {
        case .ok: return .cicadaAccent
        case .warn: return .cicadaWarn
        case .off: return .cicadaTextTertiary
        }
    }

    var body: some View {
        HStack(spacing: DesignMetrics.Spacing.s3) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.4), radius: 3)
            Text(item.label)
                .font(.subheadline)
                .foregroundStyle(.cicadaTextPrimary)
            Spacer()
            Text(item.valueText)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
    }
}

#Preview {
    ReadinessCard(items: [
        ReadinessItem(key: "triggers", label: "触发器", status: .ok, valueText: "已启用"),
        ReadinessItem(key: "notifications", label: "通知", status: .ok, valueText: "已配置"),
        ReadinessItem(key: "camera", label: "录像", status: .off, valueText: "关闭"),
        ReadinessItem(key: "activation", label: "睡眠保持", status: .warn, valueText: "空闲"),
    ])
    .padding()
    .background(.cicadaBgSurface)
    .frame(width: 500)
}
