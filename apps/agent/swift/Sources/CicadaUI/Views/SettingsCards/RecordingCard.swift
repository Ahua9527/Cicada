import SwiftUI

/// 录像设置卡：录像 Toggle + 相机权限引导 + 预览占位。
///
/// 授权状态经 `cameraAuthorizationStatus` 注入查询；`.notDetermined` 时显示
/// 「请求相机权限」按钮（`requestCameraPermission` 注入），且开启录像 Toggle 时
/// 自动触发授权请求——否则 `Sentry.startRecording()` 会因未授权静默返回，
/// 录像永远不可用。
struct RecordingCard: View {
    @ObservedObject var model: ConfigModel
    @Environment(\.cameraAuthorizationStatus) private var cameraAuthorizationStatus
    @Environment(\.requestCameraPermission) private var requestCameraPermission

    @State private var authStatus: CameraAuthorizationStatus = .authorized

    var body: some View {
        Card(title: "录像") {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
                SettingRow(title: "启用录像", desc: "警戒触发时录制摄像头画面") {
                    Toggle("", isOn: recordingEnabledBinding)
                        .labelsHidden()
                        .tint(.cicadaAccent)
                }
                cameraContent
                    .frame(height: 200)
            }
        }
        .onAppear { authStatus = cameraAuthorizationStatus() }
    }

    private var recordingEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.sentry.sentryRecordingEnabled },
            set: { newValue in
                model.sentry.sentryRecordingEnabled = newValue
                if newValue, authStatus == .notDetermined {
                    requestPermission()
                }
            }
        )
    }

    @ViewBuilder
    private var cameraContent: some View {
        switch authStatus {
        case .notDetermined:
            CameraPreviewPlaceholder(
                title: "需要相机权限",
                subtitle: "授权后警戒触发时才能录制画面"
            ) {
                if requestCameraPermission != nil {
                    Button("请求相机权限") { requestPermission() }
                        .buttonStyle(.borderedProminent)
                        .tint(.cicadaAccent)
                }
            }
        case .restricted, .denied:
            CameraPreviewPlaceholder()
        case .authorized:
            // 实时预览是既定观察点（见 overview-P4.2 已知限制），授权后先给中性占位。
            CameraPreviewPlaceholder(
                title: "相机已授权",
                subtitle: "警戒触发时将自动录制画面"
            )
        }
    }

    private func requestPermission() {
        requestCameraPermission?()
        // 系统授权弹窗异步完成，稍后重新查询状态
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            authStatus = cameraAuthorizationStatus()
        }
    }
}

#Preview {
    RecordingCard(model: ConfigModel())
        .padding()
        .background(.cicadaBgSurface)
        .frame(width: 500)
}
