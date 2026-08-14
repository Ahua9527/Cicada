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
    @Environment(\.installSleepHoldService) private var installSleepHoldService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHelp = false
    @State private var installingSleepHold = false

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
                        SettingRow(
                            title: recoveryAction == .install
                                ? String(localized: "安装 SleepHold 服务", bundle: .module)
                                : String(localized: "重新安装 SleepHold 服务", bundle: .module),
                            desc: recoveryAction == .install
                                ? String(localized: "安装后台服务，登录后自动运行；需要输入一次管理员密码", bundle: .module)
                                : String(localized: "服务已安装但无响应，重新安装可修复；需要输入一次管理员密码", bundle: .module)
                        ) {
                            Button(installingSleepHold
                                   ? String(localized: "安装中…", bundle: .module)
                                   : (recoveryAction == .install
                                      ? String(localized: "安装…", bundle: .module)
                                      : String(localized: "重新安装…", bundle: .module))) {
                                installSleepHold()
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(installingSleepHold || installSleepHoldService == nil)
                        }
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

    /// 点「安装…/重新安装…」：走宿主注入的授权弹窗安装链路（重装复用同一链路，
    /// 脚本内 launchctl unload+load 幂等覆盖，不增加卸载或迁移流程）。
    /// 安装结束后先刷新实际状态——服务可能迟到恢复；只有服务仍不可用
    /// （`recoveryAction != nil`）时才记录「授权取消/命令失败/服务未响应」具体错误，
    /// 避免服务已恢复却继续显示失败。
    private func installSleepHold() {
        guard let installSleepHoldService, !installingSleepHold else { return }
        installingSleepHold = true
        // 开始重试：清除旧安装错误。
        appModel.sleepHold.clearInstallDiagnostic()
        Task {
            let result = await installSleepHoldService()
            // 先刷新实际状态；成功恢复的 refresh 会顺带清除安装诊断。
            await appModel.refreshAll()
            if case .failure(let error) = result, appModel.sleepHold.recoveryAction != nil {
                appModel.sleepHold.setInstallDiagnostic(sleepHoldInstallMessage(error))
            }
            installingSleepHold = false
        }
    }

    private func sleepHoldInstallMessage(_ error: SleepHoldInstallError) -> String {
        switch error {
        case .authorizationCancelled, .authorizationTimedOut:
            return String(localized: "授权已取消或超时", bundle: .module)
        case .commandFailed(let detail):
            return String(localized: "安装失败：\(detail)", bundle: .module)
        case .serviceNotResponding:
            return String(localized: "已安装但服务未响应，请查看 ~/.cicada/sleephold.stderr.log", bundle: .module)
        }
    }
}

#Preview {
    MaintenancePane()
        .environmentObject(AppModel())
        .frame(width: 640, height: 600)
}
