//
//  StoreClient.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// Apple Store 底层 HTTP 客户端
enum StoreClient {
    /// 支持自定义 User-Agent，默认为 ipaDown
    static var userAgent: String {
        UserDefaults.standard.string(forKey: "customUserAgent") ?? "ipaDown"
    }

    /// 苹果服务标准的 User-Agent 列表（优先最新 Configurator，兼备容灾 UA）
    static let appleUserAgent = "Configurator/2.17 (Macintosh; OS X 15.3.1; 24D70) AppleWebKit/0620.1.16.11.6"
    static let fallbackUserAgents = [
        "Configurator/2.17 (Macintosh; OS X 15.3.1; 24D70) AppleWebKit/0620.1.16.11.6",
        "Configurator/2.17 (Macintosh; OS X 15.2; 24C5089c) AppleWebKit/0620.1.16.11.6",
        "iTunes/12.13.4.4 (Windows; Microsoft Windows 10 x64 Business Edition (Build 19045); x64) AppleWebKit/7617.5015.1001.1",
        "Configurator/2.15 (Macintosh; OS X 11.6.0; 20G165) AppleWebKit/2600.1.1"
    ]

    /// 发送 plist 格式的 POST 请求
    static func postPlist(
        url: URL,
        body: [String: Any],
        headers: [String: String] = [:],
        cookies: [HTTPCookieData] = [],
        userAgentOverride: String? = nil,
        contentType: String = "application/x-apple-plist",
        signAction: Bool = false
    ) async throws -> (data: Data, response: HTTPURLResponse, setCookies: [HTTPCookieData]) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(userAgentOverride ?? userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        // 添加系统语言环境
        if let lang = Locale.preferredLanguages.first {
            request.setValue(lang, forHTTPHeaderField: "Accept-Language")
        }

        // 添加自定义 headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // 添加 cookies
        let httpCookies = cookies.compactMap { $0.toHTTPCookie() }
        if !httpCookies.isEmpty {
            let cookieHeaders = HTTPCookie.requestHeaderFields(with: httpCookies)
            for (key, value) in cookieHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // 先生成最终请求体，再对完全相同的字节生成 SAP 签名。
        let bodyData = try PlistHelper.serialize(body)
        request.httpBody = bodyData
        if signAction {
            let signature = try await SAPSigner.sign(bodyData)
            request.setValue(signature.base64EncodedString(), forHTTPHeaderField: "X-Apple-ActionSignature")
        }

        // 使用 default config（继承系统代理设置）但禁用自动 cookie
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: NoRedirectDelegate.shared, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw IPAError.networkError("无效的 HTTP 响应")
        }

        // 允许 302 重定向（由 AuthService 处理），但对于 >= 400 的错误需抛出结构化中文异常
        if httpResponse.statusCode >= 400 {
            let errorMsg = parseHTTPError(statusCode: httpResponse.statusCode, data: data, url: url)
            throw IPAError.networkError(errorMsg)
        }

        // 从 Set-Cookie 中提取 cookies
        let newCookies = extractCookies(from: httpResponse, for: url)

        return (data, httpResponse, newCookies)
    }

    /// 发送 JSON 格式的 GET 请求
    static func getJSON(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw IPAError.networkError("HTTP \(statusCode)")
        }

        return data
    }

    /// 从 HTTP 响应中提取 Set-Cookie
    private static func extractCookies(from response: HTTPURLResponse, for url: URL) -> [HTTPCookieData] {
        guard let headerFields = response.allHeaderFields as? [String: String] else { return [] }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        return cookies.map { HTTPCookieData(from: $0) }
    }

    /// 解析 HTTP 错误并生成中文诊断信息
    private static func parseHTTPError(statusCode: Int, data: Data, url: URL) -> String {
        // 尝试从 plist 解析 Apple 官方错误消息
        if let dict = try? PlistHelper.deserialize(data) {
            if let customerMessage = dict["customerMessage"] as? String, !customerMessage.isEmpty {
                return "Apple 服务提示: \(customerMessage) (HTTP \(statusCode))"
            }
            if let failureType = dict["failureType"] as? String, !failureType.isEmpty {
                return "Apple 拒绝请求 (错误码: \(failureType), HTTP \(statusCode))"
            }
        }

        // 状态码语义化解释
        switch statusCode {
        case 401:
            return "认证凭据失效或未授权 (HTTP 401)，请刷新 Token 或重新登录"
        case 403:
            if url.path.contains("/authenticate") || url.path.contains("/auth/v1/") {
                return "Apple 拒绝了登录请求 (HTTP 403)。新版认证要求 SAP 请求签名；若当前系统已支持签名，请稍后重试或检查系统 CommerceKit 是否可用"
            }
            return "Apple 拒绝访问 (HTTP 403)，可能是会话权限、请求签名或服务端策略发生变化"
        case 404:
            return "请求的接口不存在或已被 Apple 迁移 (HTTP 404)"
        case 429:
            return "请求过于频繁，触发 Apple 安全限流 (HTTP 429)，请稍后重试"
        case 500...599:
            return "Apple 认证服务器异常 (HTTP \(statusCode))，请稍后重试"
        default:
            var bodyPreview = String(data: data.prefix(150), encoding: .utf8) ?? ""
            if bodyPreview.contains("<html") || bodyPreview.contains("<head") {
                bodyPreview = ""
            }
            return bodyPreview.isEmpty ? "HTTP \(statusCode)" : "HTTP \(statusCode) — \(bodyPreview)"
        }
    }

    /// 构建认证相关的 headers
    static func authHeaders(for account: Account) -> [String: String] {
        var headers: [String: String] = [
            "X-Dsid": account.directoryServicesId,
            "iCloud-DSID": account.directoryServicesId,
        ]
        if !account.passwordToken.isEmpty {
            headers["X-Token"] = account.passwordToken
        }
        if !account.storeFront.isEmpty {
            headers["X-Apple-Store-Front"] = "\(account.storeFront)-1"
        }
        return headers
    }
}

// MARK: - 禁止自动重定向的 URLSession Delegate

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = NoRedirectDelegate()

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // 不自动重定向，返回 nil 阻止
        completionHandler(nil)
    }
}
