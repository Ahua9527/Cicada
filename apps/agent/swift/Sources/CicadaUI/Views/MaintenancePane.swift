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
    @Environment(\.sleepHoldInstallCommand) private var sleepHoldInstallCommand
    @Environment(\.copyTextToPasteboard) private var copyTextToPasteboard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHelp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
                PaneHeader(
                    title: String(localized: "维护", bundle: .module),
                    subtitle: String(localized: "运行时路径、睡眠保持会话与诊断", bundle: .module),
                    trailing: {
                        HelpButton { showHelp = true }
                            .popover(isPresented: $showHelp, arrowEdge: .top) { HelpSheet() }
                    }
                )

                Card(title: String(localized: "运行时", bundle: .module)) {
                    SettingRow(title: String(localized: "登录时启动 Cicada", bundle: .module), desc: String(localized: "登录时自动启动应用和服务", bundle: .module)) {
                        launchAtLoginToggle.makeView()
                    }
                }

                Card(title: String(localized: "文件夹", bundle: .module)) {
                    FolderGrid()
                }

                Card(title: String(localized: "SleepHold 状态", bundle: .module)) {
                    SleepHoldCells(model: appModel.sleepHold)
                    Group {
                        if let d = appModel.sleepHold.diagnostic {
                            DiagnosticStrip(diag: d)
                                .id(d.motionKey)
                                .transition(diagnosticTransition)
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: appModel.sleepHold.diagnostic?.motionKey)

                    if let recoveryAction = appModel.sleepHold.recoveryAction {
                        // 沙箱应用无法自动注册 root LaunchDaemon（issue #9），
                        // 安装/修复退化为可复制命令 + 可选中文本。
                        SettingRow(
                            title: recoveryAction == .install
                                ? String(localized: "安装 SleepHold 服务", bundle: .module)
                                : String(localized: "重新安装 SleepHold 服务", bundle: .module),
                            desc: recoveryAction == .install
                                ? String(localized: "沙箱限制无法自动安装，请在终端执行命令：", bundle: .module)
                                : String(localized: "服务已安装但无响应，请在终端执行命令重装：", bundle: .module)
                        ) {
                            if let copyTextToPasteboard {
                                Button(String(localized: "复制命令", bundle: .module)) {
                                    copyTextToPasteboard(sleepHoldInstallCommand)
                                }
                                .buttonStyle(PrimaryButtonStyle())
                            }
                        }
                        Text(sleepHoldInstallCommand)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.cicadaTextSecondary)
                            .textSelection(.enabled)
                            .padding(.horizontal, DesignMetrics.Spacing.s3)
                            .padding(.vertical, DesignMetrics.Spacing.s2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.cicadaBgBase)
                            .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.sm))
                            .accessibilityLabel(sleepHoldInstallCommand)
                    }
                }

                Card(title: String(localized: "诊断", bundle: .module)) {
                    Button(String(localized: "运行启动检查", bundle: .module)) {
                        if let runStartupChecks {
                            runStartupChecks()
                        } else {
                            Task { await appModel.refreshAll() }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } content: {
                    Group {
                        if let d = appModel.startupDiagnostic {
                            DiagnosticStrip(diag: d)
                                .id(d.motionKey)
                                .transition(diagnosticTransition)
                        } else {
                            Text(String(localized: "暂无诊断信息", bundle: .module))
                                .font(.caption)
                                .foregroundStyle(.cicadaTextTertiary)
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: appModel.startupDiagnostic?.motionKey)
                }
            }
            .padding(DesignMetrics.Spacing.s6)
        }
    }

    private var diagnosticTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

}

#Preview {
    MaintenancePane()
        .environmentObject(AppModel())
        .frame(width: 640, height: 600)
}
