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
    
    /// 苹果服务标准的 User-Agent (Configurator)，用于确保核心接口兼容性
    static let appleUserAgent = "Configurator/2.17 (Macintosh; OS X 15.2; 24C5089c) AppleWebKit/0620.1.16.11.6"
    
    /// 发送 plist 格式的 POST 请求
    static func postPlist(
        url: URL,
        body: [String: Any],
        headers: [String: String] = [:],
        cookies: [HTTPCookieData] = [],
        userAgentOverride: String? = nil
    ) async throws -> (data: Data, response: HTTPURLResponse, setCookies: [HTTPCookieData]) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgentOverride ?? userAgent, forHTTPHeaderField: "User-Agent")
        
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
        
        // 序列化请求体
        request.httpBody = try PlistHelper.serialize(body)
        
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
        
        // 允许 302 重定向（由 AuthService 处理），但对于 >400 的错误需抛出异常
        if httpResponse.statusCode >= 400 {
            let bodyPreview = String(data: data.prefix(200), encoding: .utf8) ?? "（二进制数据）"
            throw IPAError.networkError("HTTP \(httpResponse.statusCode) — \(bodyPreview)")
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
