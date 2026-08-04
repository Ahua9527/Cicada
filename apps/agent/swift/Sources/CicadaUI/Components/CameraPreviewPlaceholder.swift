import SwiftUI

/// 相机预览占位视图。
///
/// 实际相机预览（授权后）由 Xcode 宿主的 `CameraSessionController` +
/// `CameraPreviewView`（NSView）提供，CicadaUI 只做占位。
/// `overlayContent` 可叠加操作按钮（如「请求相机权限」）。
struct CameraPreviewPlaceholder<OverlayContent: View>: View {
    var title: String = String(localized: "相机预览未授权", bundle: .module)
    var subtitle: String = String(localized: "请在系统设置中授予摄像头访问权限", bundle: .module)
    @ViewBuilder var overlayContent: OverlayContent

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.lg)
                .fill(Color.black)

            // 顶部高光
            LinearGradient(
                colors: [Color.white.opacity(0.08), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.lg))

            VStack(spacing: DesignMetrics.Spacing.s3) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.white.opacity(0.4))
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.5))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.3))
                overlayContent
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.lg)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

extension CameraPreviewPlaceholder where OverlayContent == EmptyView {
    init(title: String = String(localized: "相机预览未授权", bundle: .module), subtitle: String = String(localized: "请在系统设置中授予摄像头访问权限", bundle: .module)) {
        self.init(title: title, subtitle: subtitle, overlayContent: { EmptyView() })
    }
}

#Preview {
    CameraPreviewPlaceholder()
        .frame(width: 320, height: 240)
        .padding()
        .background(.cicadaBgSurface)
}
