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
    @Environment(\.scenePhase) private var scenePhase

    @State private var authStatus: CameraAuthorizationStatus?
    @State private var isRequestingPermission = false
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
                    .id(permissionPhase)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: permissionPhase)
        .task {
            refreshAuthorizationState()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                refreshAuthorizationState()
            }
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
        switch permissionPhase {
        case .checking:
            CameraPreviewPlaceholder(
                title: String(localized: "正在检查相机权限", bundle: .module),
                subtitle: String(localized: "正在读取系统相机访问状态", bundle: .module)
            )
        case .requesting:
            CameraPreviewPlaceholder(
                title: String(localized: "等待系统授权", bundle: .module),
                subtitle: String(localized: "请在系统弹窗中选择允许或不允许", bundle: .module)
            )
        case .status(.notDetermined):
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
        case .status(.restricted), .status(.denied):
            CameraPreviewPlaceholder()
        case .status(.authorized):
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
        guard let requestCameraPermission else { return }
        isRequestingPermission = true
        Task { @MainActor in
            authStatus = await requestCameraPermission()
            cameras = cameraOptions()
            isRequestingPermission = false
        }
    }

    private func refreshAuthorizationState() {
        authStatus = cameraAuthorizationStatus()
        cameras = cameraOptions()
    }

    private var permissionPhase: PermissionPhase {
        if isRequestingPermission { return .requesting }
        guard let authStatus else { return .checking }
        return .status(authStatus)
    }

    private enum PermissionPhase: Hashable {
        case checking
        case requesting
        case status(CameraAuthorizationStatus)
    }
}

#Preview {
    RecordingCard(model: ConfigModel())
        .padding()
        .background(.cicadaBgSurface)
        .frame(width: 500)
}
