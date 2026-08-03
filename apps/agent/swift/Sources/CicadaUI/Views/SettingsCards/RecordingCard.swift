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
    @Environment(\.cameraOptions) private var cameraOptions

    @State private var authStatus: CameraAuthorizationStatus = .authorized
    @State private var cameras: [CameraOption] = []

    var body: some View {
        Card(title: String(localized: "录像", bundle: .module)) {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
                SettingRow(title: String(localized: "启用录像", bundle: .module), desc: String(localized: "警戒触发时录制摄像头画面", bundle: .module)) {
                    Toggle("", isOn: recordingEnabledBinding)
                        .labelsHidden()
                        .tint(.cicadaAccent)
                }
                cameraContent
                    .frame(height: 200)
            }
        }
        .onAppear {
            authStatus = cameraAuthorizationStatus()
            cameras = cameraOptions()
        }
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
                title: String(localized: "需要相机权限", bundle: .module),
                subtitle: String(localized: "授权后警戒触发时才能录制画面", bundle: .module)
            ) {
                if requestCameraPermission != nil {
                    Button(String(localized: "请求相机权限", bundle: .module)) { requestPermission() }
                        .buttonStyle(.borderedProminent)
                        .tint(.cicadaAccent)
                }
            }
        case .restricted, .denied:
            CameraPreviewPlaceholder()
        case .authorized:
            // 实时预览是既定观察点（见 overview-P4.2 已知限制），授权后先给中性占位 +
            // 设备选择器：多摄像头 Mac 可切换 sentryRecordingDevice，否则静默回退内置/默认。
            CameraPreviewPlaceholder(
                title: String(localized: "相机已授权", bundle: .module),
                subtitle: String(localized: "警戒触发时将自动录制画面", bundle: .module)
            ) {
                if cameras.count > 1 {
                    Picker(selection: $model.sentry.sentryRecordingDevice) {
                        Text(String(localized: "默认", bundle: .module)).tag(String?.none)
                        ForEach(cameras) { camera in
                            Text(camera.name).tag(Optional(camera.id))
                        }
                    } label: {
                        Text(String(localized: "录像设备", bundle: .module))
                    }
                    .pickerStyle(.menu)
                } else {
                    EmptyView()
                }
            }
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
