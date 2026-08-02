import SwiftUI

/// 维护页：运行时 / 文件夹 / SleepHold 状态 / 诊断 四个 Card。
///
/// 开机自启项与「运行启动检查」按钮通过 `@Environment` 注入宿主行为：
/// - `launchAtLoginToggle`：宿主注入真实 `LaunchAtLogin.Toggle`（写 SMLoginItemSetEnabled）。
///   库默认占位仅写 `@AppStorage("launchAtLogin")`，不真正注册自启。
/// - `runStartupChecks`：宿主注入 `AppDelegate.runStartupChecks()` 走启动诊断链路。
///   `nil`（库默认）时回退到 `appModel.refreshAll()` 刷新 IPC 快照。
/// - `folderActions`：`FolderGrid` 的 6 个按钮行为（见 FolderGrid.swift）。
struct MaintenancePane: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.launchAtLoginToggle) private var launchAtLoginToggle
    @Environment(\.runStartupChecks) private var runStartupChecks

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
                PaneHeader(
                    title: "维护",
                    subtitle: "运行时路径、睡眠保持会话与诊断",
                    trailing: { HelpButton() }
                )

                Card(title: "运行时") {
                    SettingRow(title: "登录时启动 Cicada", desc: "登录时自动启动应用和服务") {
                        launchAtLoginToggle.makeView()
                    }
                }

                Card(title: "文件夹") {
                    FolderGrid()
                }

                Card(title: "SleepHold 状态") {
                    SleepHoldCells(model: appModel.sleepHold)
                }

                Card(title: "诊断") {
                    Button("运行启动检查") {
                        if let runStartupChecks {
                            runStartupChecks()
                        } else {
                            Task { await appModel.refreshAll() }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } content: {
                    if let d = appModel.sleepHold.diagnostic {
                        DiagnosticStrip(diag: d)
                    } else {
                        Text("暂无诊断信息")
                            .font(.caption)
                            .foregroundStyle(.cicadaTextTertiary)
                    }
                }
            }
            .padding(DesignMetrics.Spacing.s6)
        }
    }
}

#Preview {
    MaintenancePane()
        .environmentObject(AppModel())
        .frame(width: 640, height: 600)
}