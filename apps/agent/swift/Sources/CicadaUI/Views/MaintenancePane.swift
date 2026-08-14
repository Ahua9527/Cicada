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

                    if !appModel.sleepHold.serviceInstalled {
                        SettingRow(
                            title: String(localized: "安装 SleepHold 服务", bundle: .module),
                            desc: String(localized: "安装后台服务，登录后自动运行；需要输入一次管理员密码", bundle: .module)
                        ) {
                            Button(installingSleepHold
                                   ? String(localized: "安装中…", bundle: .module)
                                   : String(localized: "安装…", bundle: .module)) {
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

    /// 点「安装…」：走宿主注入的授权弹窗安装链路，完成后刷新全量状态。
    /// 失败按 `SleepHoldInstallError` 分类翻成本地化诊断写回 SleepHold 诊断条；
    /// 成功则靠 refreshAll 自然消条、状态卡转正常。
    private func installSleepHold() {
        guard let installSleepHoldService, !installingSleepHold else { return }
        installingSleepHold = true
        Task {
            let result = await installSleepHoldService()
            if case .failure(let error) = result {
                appModel.sleepHold.setDiagnostic(sleepHoldInstallMessage(error))
            }
            await appModel.refreshAll()
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
