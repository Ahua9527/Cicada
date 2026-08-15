import CicadaCore
import Foundation
import SystemConfiguration

/// SleepHold 安装上下文：写入 launchd plist 的 socket/日志路径与属主必须指向
/// **发起安装的登录用户**，而不是进程身份——`sudo cicada advanced sleep install`
/// 时进程是 root，若直接用 getuid()/NSHomeDirectory() 会把 daemon 配到
/// /var/root 且 socket 属主 root:root，App 端永远 ENOENT（真机复现）。
///
/// 解析顺序：
/// 1. 非 root 进程（推荐用法：直接运行，install() 内部按需 sudo）→ 进程自身；
/// 2. root 且带 SUDO_UID/SUDO_GID（用户加了 sudo）→ 还原调用者；
/// 3. root 且无 SUDO_*（如 AppleScript 管理员授权提权）→ 当前 console 登录用户；
/// 4. 都拿不到 → 明确报错，提示去掉 sudo 直接运行。
struct SleepHoldInstallContext: Equatable {
    let uid: uid_t
    let gid: gid_t
    let homeDirectory: String

    /// 该用户的 `~/.cicada` 根。
    var cicadaHome: String { homeDirectory + "/.cicada" }
    var runDir: String { cicadaHome + "/run" }
    var socketPath: String { runDir + "/sleephold.sock" }
    var stdoutPath: String { cicadaHome + "/sleephold.stdout.log" }
    var stderrPath: String { cicadaHome + "/sleephold.stderr.log" }

    static func resolve(
        processUID: uid_t = getuid(),
        processGID: gid_t = getgid(),
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeForUID: (uid_t) -> String? = { uid in
            guard let pw = getpwuid(uid), let dir = pw.pointee.pw_dir else { return nil }
            return String(cString: dir)
        },
        consoleUser: () -> (uid: uid_t, gid: gid_t)? = currentConsoleUser
    ) throws -> SleepHoldInstallContext {
        if processUID != 0 {
            return SleepHoldInstallContext(
                uid: processUID,
                gid: processGID,
                homeDirectory: homeForUID(processUID) ?? RuntimePaths.home
            )
        }
        if let uid = env["SUDO_UID"].flatMap(UInt32.init), uid != 0,
           let gid = env["SUDO_GID"].flatMap(UInt32.init), gid != 0,
           let home = homeForUID(uid_t(uid))
        {
            return SleepHoldInstallContext(uid: uid_t(uid), gid: uid_t(gid), homeDirectory: home)
        }
        if let console = consoleUser(), let home = homeForUID(console.uid) {
            return SleepHoldInstallContext(uid: console.uid, gid: console.gid, homeDirectory: home)
        }
        throw CicadaError.command(
            "无法确定安装目标用户（root 运行且无 SUDO_UID/console 会话）。请去掉 sudo，以登录用户身份直接运行：cicada advanced sleep install（安装过程会按需提示输入管理员密码）"
        )
    }

    /// 当前 console 图形会话用户；loginwindow/_mbsetupuser 视为无有效会话。
    private static func currentConsoleUser() -> (uid: uid_t, gid: gid_t)? {
        var uid = uid_t(0)
        var gid = gid_t(0)
        guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String? else { return nil }
        guard uid != 0, name != "loginwindow", name != "_mbsetupuser" else { return nil }
        return (uid, gid)
    }
}
