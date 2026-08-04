import XCTest
@testable import CicadaUI

/// BarkClient URL 注入修复的单测覆盖。
///
/// 覆盖场景：
/// - 中文 reason（title/body）经 URLQueryItem 正确 percent-encode。
/// - 含斜杠的 body 不应污染 URL path（注入修复回归）。
/// - 空 body 不应让 URL 退化。
/// - 非法 level 被枚举校验拦截，不发出请求。
/// - 合法 level（active/critical/timeSensitive/normal）通过校验。
/// - 2xx 响应通过；非 2xx 抛 `.badStatus`。
final class BarkClientTests: XCTestCase {

    // MARK: - 测试用 URLSession：拦截请求并断言 URL/query

    /// 记录最后一次请求的 URL，并返回指定 HTTP 状态码的空响应。
    private final class URLProbe: URLProtocol {
        static var lastURL: URL?
        static var lastMethod: String?
        static var statusCode: Int = 200

        static func reset() {
            lastURL = nil
            lastMethod = nil
            statusCode = 200
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lastURL = request.url
            Self.lastMethod = request.httpMethod
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: Self.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func makeSession() -> URLSession {
        URLProbe.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProbe.self]
        return URLSession(configuration: config)
    }

    override func tearDown() {
        URLProbe.reset()
        super.tearDown()
    }

    // MARK: - URL 构造

    func testChineseTitleAndBodyArePercentEncodedAsQueryItems() async throws {
        let session = makeSession()
        URLProbe.statusCode = 200
        let client = BarkClient(
            endpoint: URL(string: "https://api.day.app/abcdef")!,
            session: session
        )

        try await client.push(title: "警戒触发", body: "检测到异常：合盖", level: "critical")

        let url = try XCTUnwrap(URLProbe.lastURL)
        XCTAssertEqual(URLProbe.lastMethod, "GET")
        // 中文应被 percent-encode，原文字不应直接出现在 URL 中。
        XCTAssertFalse(url.absoluteString.contains("警戒触发"))
        XCTAssertFalse(url.absoluteString.contains("检测到异常"))
        // 解码后应能还原原始字符串。
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = comps?.queryItems ?? []
        let title = query.first { $0.name == "title" }?.value
        let body = query.first { $0.name == "body" }?.value
        XCTAssertEqual(title, "警戒触发")
        XCTAssertEqual(body, "检测到异常：合盖")
        XCTAssertEqual(query.first { $0.name == "level" }?.value, "critical")
        XCTAssertEqual(query.first { $0.name == "group" }?.value, "Cicada - Mac")
        XCTAssertEqual(query.first { $0.name == "call" }?.value, "1")
        XCTAssertEqual(query.first { $0.name == "isArchive" }?.value, "1")
    }

    func testBodyWithSlashesStaysInQueryAndDoesNotPollutePath() async throws {
        let session = makeSession()
        URLProbe.statusCode = 200
        let client = BarkClient(
            endpoint: URL(string: "https://api.day.app/abcdef")!,
            session: session
        )

        try await client.push(title: "t", body: "a/b/c", level: "active")

        let url = try XCTUnwrap(URLProbe.lastURL)
        // body 中的 `/` 应作为 query 值被 percent-encode，绝不能成为 path 段。
        // path 仍保持 Bark key（/abcdef），不出现 `a`、`b`、`c` 作为独立路径段。
        let path = url.path
        XCTAssertEqual(path, "/abcdef")
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let body = comps?.queryItems?.first { $0.name == "body" }?.value
        XCTAssertEqual(body, "a/b/c")
    }

    func testEmptyBodyDoesNotCollapseURL() async throws {
        let session = makeSession()
        URLProbe.statusCode = 200
        let client = BarkClient(
            endpoint: URL(string: "https://api.day.app/abcdef")!,
            session: session
        )

        try await client.push(title: "hello", body: "", level: "normal")

        let url = try XCTUnwrap(URLProbe.lastURL)
        XCTAssertEqual(url.path, "/abcdef")
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let title = comps?.queryItems?.first { $0.name == "title" }?.value
        let body = comps?.queryItems?.first { $0.name == "body" }?.value
        XCTAssertEqual(title, "hello")
        XCTAssertEqual(body, "")
    }

    // MARK: - level 枚举校验

    func testInvalidLevelIsRejectedBeforeRequest() async throws {
        let session = makeSession()
        URLProbe.statusCode = 200
        let client = BarkClient(
            endpoint: URL(string: "https://api.day.app/abcdef")!,
            session: session
        )

        do {
            try await client.push(title: "t", body: "b", level: "DROP TABLE users; --")
            XCTFail("非法 level 应被拒绝")
        } catch let BarkClient.BarkError.invalidLevel(value) {
            XCTAssertEqual(value, "DROP TABLE users; --")
        }
        // 非法 level 不应发起任何网络请求。
        XCTAssertNil(URLProbe.lastURL)
    }

    func testInvalidLevelWithSlashIsRejected() async throws {
        let session = makeSession()
        let client = BarkClient(
            endpoint: URL(string: "https://api.day.app/abcdef")!,
            session: session
        )
        do {
            try await client.push(title: "t", body: "b", level: "../")
            XCTFail("非法 level 应被拒绝")
        } catch BarkClient.BarkError.invalidLevel {
            // 期望路径
        }
        XCTAssertNil(URLProbe.lastURL)
    }

    func testAllAllowedLevelsAreAccepted() async throws {
        let session = makeSession()
        URLProbe.statusCode = 200
        let client = BarkClient(
            endpoint: URL(string: "https://api.day.app/abcdef")!,
            session: session
        )
        for level in ["active", "critical", "timeSensitive", "normal"] {
            try await client.push(title: "t", body: "b", level: level)
            let comps = URLComponents(url: try XCTUnwrap(URLProbe.lastURL), resolvingAgainstBaseURL: false)
            XCTAssertEqual(comps?.queryItems?.first { $0.name == "level" }?.value, level)
            URLProbe.lastURL = nil
        }
    }

    // MARK: - 响应码

    func testBadStatusThrows() async throws {
        let session = makeSession()
        URLProbe.statusCode = 500
        let client = BarkClient(
            endpoint: URL(string: "https://api.day.app/abcdef")!,
            session: session
        )
        do {
            try await client.push(title: "t", body: "b")
            XCTFail("非 2xx 应抛 badStatus")
        } catch BarkClient.BarkError.badStatus {
            // 期望
        }
    }

    func testDefaultLevelIsCritical() async throws {
        let session = makeSession()
        URLProbe.statusCode = 200
        let client = BarkClient(
            endpoint: URL(string: "https://api.day.app/abcdef")!,
            session: session
        )
        try await client.push(title: "t", body: "b")
        let comps = URLComponents(url: try XCTUnwrap(URLProbe.lastURL), resolvingAgainstBaseURL: false)
        XCTAssertEqual(comps?.queryItems?.first { $0.name == "level" }?.value, "critical")
    }
}