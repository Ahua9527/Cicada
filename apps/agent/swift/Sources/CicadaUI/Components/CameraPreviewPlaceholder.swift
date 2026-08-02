import SwiftUI

/// 相机未授权占位视图。
///
/// 实际相机预览（授权后）由 Xcode 宿主的 `CameraSessionController` +
/// `CameraPreviewView`（NSView）提供，CicadaUI 只做占位。
struct CameraPreviewPlaceholder: View {
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
                Text("相机预览未授权")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.5))
                Text("请在系统设置中授予摄像头访问权限")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.lg)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

#Preview {
    CameraPreviewPlaceholder()
        .frame(width: 320, height: 240)
        .padding()
        .background(.cicadaBgSurface)
}