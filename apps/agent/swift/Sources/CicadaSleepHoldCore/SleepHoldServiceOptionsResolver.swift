import Darwin
import Foundation
import SystemConfiguration

/// daemon 运行属主：socket chown 目标与 home 路径推导来源。
public struct SleepHoldOwnerInfo: Equatable {
    public let uid: uid_t
    public let gid: gid_t
    public let homeDirectory: String

    public init(uid: uid_t, gid: gid_t, homeDirectory: String) {
        self.uid = uid
        self.gid = gid
        self.homeDirectory = homeDirectory
    }
}

/// 已解析的 daemon 启动参数。
public struct ResolvedSleepHoldServiceOptions: Equatable {
    public let socketPath: String
    public let ownerUID: uid_t
    public let ownerGID: gid_t
    /// home 仅在经 console 用户推导时携带（daemon 据此自举日志重定向——
    /// 静态内嵌 plist 无法携带 per-user 的 StandardOut/ErrPath）。
    public let homeDirectory: String?

    public init(socketPath: String, ownerUID: uid_t, ownerGID: gid_t, homeDirectory: String?) {
        self.socketPath = socketPath
        self.ownerUID = ownerUID
        self.ownerGID = ownerGID
        self.homeDirectory = homeDirectory
    }
}

/// cicada-sleephold 启动参数解析：
/// 命令行 `--socket/--uid/--gid` 缺省时从 console 用户推导补齐。
///
/// 背景：SMAppService 内嵌 daemon plist 是静态签名产物，无法像旧
/// `SleepHoldServiceManager.prepareInstall()` 那样按机器生成 uid/gid/socket 路径。
/// 旧 plist（CLI sudo 安装）三参数齐全，原样使用，行为不变。
public enum SleepHoldServiceOptionsResolver {
    /// 默认 socket 路径：`<home>/.cicada/run/sleephold.sock`。
    /// 与 CicadaCore.RuntimePaths 的 runDir/sleepHoldSocketPath 约定一致——daemon 是独立
    /// root 进程（CicadaSleepHoldCore 不依赖 CicadaCore），字面量在此重复，改动需同步。
    public static func defaultSocketPath(homeDirectory: String) -> String {
        homeDirectory + "/.cicada/run/sleephold.sock"
    }

    /// 合并命令行覆盖与 console 用户推导：
    /// - 三参数全部显式提供（CLI sudo 安装的旧 plist）：原样使用，不触碰 console 用户；
    /// - 任一缺省（SMAppService 静态 plist 零参数启动）：用 console 用户补齐缺失字段；
    /// - console 用户暂不可得（开机 RunAtLoad 早于登录）：返回 nil，调用方稍后重试。
    public static func resolve(
        socketPath: String?,
        ownerUID: uid_t?,
        ownerGID: gid_t?,
        consoleUser: () -> SleepHoldOwnerInfo?
    ) -> ResolvedSleepHoldServiceOptions? {
        if let socketPath, let ownerUID, let ownerGID {
            return ResolvedSleepHoldServiceOptions(
                socketPath: socketPath,
                ownerUID: ownerUID,
                ownerGID: ownerGID,
                homeDirectory: nil
            )
        }
        guard let user = consoleUser() else { return nil }
        return ResolvedSleepHoldServiceOptions(
            socketPath: socketPath ?? defaultSocketPath(homeDirectory: user.homeDirectory),
            ownerUID: ownerUID ?? user.uid,
            ownerGID: ownerGID ?? user.gid,
            homeDirectory: user.homeDirectory
        )
    }

    /// 当前 console 用户。loginwindow（登录窗）、_mbsetupuser（初始化助手）与 root
    /// 均视为无真实用户会话。两个查询点可注入，便于单测。
    public static func currentConsoleUser(
        consoleUserName: (UnsafeMutablePointer<uid_t>, UnsafeMutablePointer<gid_t>) -> String? = {
            SCDynamicStoreCopyConsoleUser(nil, $0, $1) as? String
        },
        homeDirectory: (uid_t) -> String? = { uid in
            getpwuid(uid).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } }
        }
    ) -> SleepHoldOwnerInfo? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard let name = consoleUserName(&uid, &gid),
              name != "loginwindow",
              name != "_mbsetupuser",
              uid != 0,
              let home = homeDirectory(uid) else {
            return nil
        }
        return SleepHoldOwnerInfo(uid: uid, gid: gid, homeDirectory: home)
    }
}
