import SwiftUI

/// 通用容器卡片，供设置、维护区复用。
struct Card<Header: View, Content: View>: View {
    let title: String
    @ViewBuilder let trailing: Header
    @ViewBuilder let content: () -> Content

    init(title: String, @ViewBuilder trailing: () -> Header, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing()
        self.content = content
    }

    /// 无 header（trailing）时的便捷构造，避免调用点写 `Card(title:) { EmptyView() }`。
    init(title: String, @ViewBuilder content: @escaping () -> Content) where Header == EmptyView {
        self.title = title
        self.trailing = EmptyView()
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cicadaTextSecondary)
                Spacer()
                trailing
            }
            content()
        }
        .padding(DesignMetrics.Spacing.s5)
        .background(Color.cicadaBgSurface2)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.lg)
                .stroke(.cicadaBorderSubtle, lineWidth: 1)
        )
    }
}

#Preview {
    Card(title: "触发器") {
        VStack(alignment: .leading, spacing: 8) {
            Text("合盖触发")
                .font(.subheadline)
            Text("电源断开触发")
                .font(.subheadline)
        }
    }
    .padding()
    .background(.cicadaBgSurface)
    .frame(width: 400)
}