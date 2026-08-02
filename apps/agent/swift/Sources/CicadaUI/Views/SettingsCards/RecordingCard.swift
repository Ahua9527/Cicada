import SwiftUI

/// 录像设置卡：录像 Toggle + 相机预览占位。
struct RecordingCard: View {
    @ObservedObject var model: ConfigModel

    var body: some View {
        Card(title: "录像") {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
                SettingRow(title: "启用录像", desc: "警戒触发时录制摄像头画面") {
                    Toggle("", isOn: $model.sentry.sentryRecordingEnabled)
                        .labelsHidden()
                        .tint(.cicadaAccent)
                }
                CameraPreviewPlaceholder()
                    .frame(height: 200)
            }
        }
    }
}

#Preview {
    RecordingCard(model: ConfigModel())
        .padding()
        .background(.cicadaBgSurface)
        .frame(width: 500)
}
