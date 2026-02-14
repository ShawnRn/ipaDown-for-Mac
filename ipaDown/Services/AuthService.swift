//
//  AuthService.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// Apple 账号认证服务
enum AuthService {
    private static let logger = AppLogger.shared
    
    /// 认证（登录）Apple 账号
    static func authenticate(
        email: String,
        password: String,
        code: String = "",
        existingCookies: [HTTPCookieData] = [],
        existingStoreFront: String = ""
    ) async throws -> Account {
        let guid = DeviceIdentifier.getOrCreate()
        
        var currentURL = makeAuthURL(guid: guid)
        var cookies = existingCookies
        var storeFront = existingStoreFront
        var currentAttempt = 0
        var redirectAttempt = 0
        let maxAttempts = 2
        let maxRedirects = 3
        var lastError: Error?
        
        while currentAttempt < maxAttempts, redirectAttempt <= maxRedirects {
            currentAttempt += 1
            
            do {
                let body: [String: Any] = [
                    "appleId": email,
                    "attempt": code.isEmpty ? "4" : "2",
                    "createSession": "true",
                    "guid": guid,
                    "password": "\(password)\(code)",
                    "rmp": "0",
                    "why": "signIn",
                ]
                
                logger.info("登录", "请求 URL: \(currentURL.absoluteString)")
                
                let (data, response, newCookies) = try await StoreClient.postPlist(
                    url: currentURL,
                    body: body,
                    cookies: cookies,
                    userAgentOverride: StoreClient.appleUserAgent
                )
                
                // 合并 cookies
                mergeCookies(&cookies, with: newCookies)
                
                // 提取 Store Front
                if let sfHeader = response.value(forHTTPHeaderField: "x-set-apple-store-front"),
                   let sf = sfHeader.components(separatedBy: "-").first, !sf.isEmpty {
                    storeFront = sf
                }
                
                // 调试：记录响应信息
                let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? "无"
                logger.info("登录", "HTTP \(response.statusCode), Content-Type: \(contentType), Body: \(data.count) bytes")
                
                // 打印响应内容（前 500 字节）用于调试
                if let bodyStr = String(data: data.prefix(500), encoding: .utf8) {
                    logger.info("登录", "响应内容: \(bodyStr)")
                }
                
                // 处理重定向
                if response.statusCode == 302 {
                    if let location = response.value(forHTTPHeaderField: "Location"),
                       let redirectURL = URL(string: location) {
                        logger.info("登录", "重定向到: \(location)")
                        currentURL = redirectURL
                        currentAttempt -= 1
                        redirectAttempt += 1
                        continue
                    }
                    throw IPAError.authenticationFailed("重定向地址无效")
                }
                
                // 检查响应是否为空
                guard !data.isEmpty else {
                    throw IPAError.authenticationFailed("响应为空 (HTTP \(response.statusCode))")
                }
                
                // 解析响应
                let dict: [String: Any]
                do {
                    dict = try PlistHelper.deserialize(data)
                } catch {
                    // 如果不是 plist，尝试看是否是 HTML/文本
                    let bodyPreview = String(data: data.prefix(200), encoding: .utf8) ?? "（二进制数据）"
                    throw IPAError.authenticationFailed("Apple 返回了非 plist 格式: HTTP \(response.statusCode) — \(bodyPreview)")
                }
                
                // 检查是否需要两步验证
                if let failureType = dict["failureType"] as? String,
                   failureType.isEmpty,
                   code.isEmpty,
                   let customerMessage = dict["customerMessage"] as? String,
                   customerMessage == "MZFinance.BadLogin.Configurator_message" {
                    throw IPAError.codeRequired
                }
                
                // 检查失败信息
                let failureMessage = (dict["dialog"] as? [String: Any])?["explanation"] as? String
                    ?? dict["customerMessage"] as? String
                
                guard let accountInfo = dict["accountInfo"] as? [String: Any] else {
                    throw IPAError.authenticationFailed(failureMessage ?? "缺少账号信息")
                }
                
                guard let addressInfo = accountInfo["address"] as? [String: Any] else {
                    throw IPAError.authenticationFailed(failureMessage ?? "缺少地址信息")
                }
                
                guard let passwordToken = dict["passwordToken"] as? String,
                      let dsPersonId = dict["dsPersonId"] as? String else {
                    throw IPAError.authenticationFailed(failureMessage ?? "缺少认证 Token")
                }
                
                let account = Account(
                    email: email,
                    password: password,
                    appleId: (accountInfo["appleId"] as? String) ?? email,
                    storeFront: storeFront,
                    firstName: (addressInfo["firstName"] as? String) ?? "",
                    lastName: (addressInfo["lastName"] as? String) ?? "",
                    passwordToken: passwordToken,
                    directoryServicesId: "\(dsPersonId)",
                    cookies: cookies
                )
                
                logger.success("登录", "登录成功: \(account.displayName)")
                return account
                
            } catch {
                lastError = error
                if error is IPAError { throw error }
            }
        }
        
        throw lastError ?? IPAError.authenticationFailed("未知原因")
    }
    
    /// 刷新账号 Token（使用已有的 cookie 和密码）
    static func refreshToken(for account: Account) async throws -> Account {
        logger.info("登录", "正在刷新 Token: \(account.email)")
        return try await authenticate(
            email: account.email,
            password: account.password,
            code: "",
            existingCookies: account.cookies,
            existingStoreFront: account.storeFront
        )
    }
    
    // MARK: - Private
    
    private static func makeAuthURL(guid: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "auth.itunes.apple.com"
        components.path = "/auth/v1/native/fast"
        components.queryItems = [URLQueryItem(name: "guid", value: guid)]
        return components.url!
    }
    
    private static func mergeCookies(_ existing: inout [HTTPCookieData], with newCookies: [HTTPCookieData]) {
        for newCookie in newCookies {
            existing.removeAll { $0.name == newCookie.name && $0.domain == newCookie.domain }
            existing.append(newCookie)
        }
    }
}
