import Foundation

/// Bark HTTP 推送独立封装（async/await + URLSession）。
///
/// 参考现有 `Sentry.makeBarkRequest` 的 URL 构造方式：
/// GET 请求，路径为 `endpoint/title/body`，queryItems 含 level/group/call/isArchive。
struct BarkClient {
    let endpoint: URL
    let session: URLSession

    /// 创建 BarkClient。
    /// - Parameters:
    ///   - endpoint: Bark 服务端基础 URL（如 `https://api.day.app/xxx`）。
    ///   - session: 自定义 URLSession（默认 `.shared`，单测可注入 mock）。
    init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    /// 推送一条 Bark 消息。
    /// - Parameters:
    ///   - title: 消息标题。
    ///   - body: 消息正文。
    ///   - level: 通知级别（默认 "critical"），必须属于 `Level.allowedRawValues`。
    func push(title: String, body: String, level: String = Level.critical.rawValue) async throws {
        // 校验 level 枚举值，拒绝任意字符串注入。
        guard Level(rawValue: level) != nil else {
            throw BarkError.invalidLevel(level)
        }

        // 用 URLComponents 构造，title/body 作为 queryItem 由系统 percent-encode，
        // 避免含中文/斜杠/空格的字符串直接拼到 path 造成 URL 路径注入。
        guard var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw BarkError.invalidURL
        }
        // 保留 endpoint 既有 path（如 /xxx），把 title/body 并入 query 以自动编码。
        var queryItems = comps.queryItems ?? []
        queryItems.append(URLQueryItem(name: "title", value: title))
        queryItems.append(URLQueryItem(name: "body", value: body))
        queryItems.append(URLQueryItem(name: "level", value: level))
        queryItems.append(URLQueryItem(name: "group", value: "Cicada - Mac"))
        queryItems.append(URLQueryItem(name: "call", value: "1"))
        queryItems.append(URLQueryItem(name: "isArchive", value: "1"))
        comps.queryItems = queryItems

        guard let finalURL = comps.url else {
            throw BarkError.invalidURL
        }

        var req = URLRequest(url: finalURL)
        req.httpMethod = "GET"

        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BarkError.badStatus
        }
    }

    /// Bark 通知级别白名单，对照 Bark 官方文档。
    enum Level: String {
        case active
        case critical
        case timeSensitive
        case normal
    }

    /// Bark 推送错误。
    enum BarkError: Error, Equatable {
        case badStatus
        case invalidURL
        case invalidLevel(String)
    }
}