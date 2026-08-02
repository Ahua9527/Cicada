import SwiftUI

/// 版本号标签，读 Bundle.main 版本信息。
struct VersionTag: View {
    var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.cicadaBorderSubtle)
                .frame(height: 1)
            Text("Cicada v\(version) (build \(build)) · macOS \(osVersion)")
                .font(.caption.monospaced())
                .foregroundStyle(.cicadaTextTertiary)
                .padding(.top, DesignMetrics.Spacing.s3)
        }
    }
}

#Preview {
    VersionTag()
        .padding()
        .background(.cicadaBgSurface)
        .frame(width: 400)
}