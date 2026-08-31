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

        // 1. 尝试使用现有 Cookie 与配置进行认证
        do {
            return try await executeAuthenticationFlow(
                email: email,
                password: password,
                code: code,
                cookies: existingCookies,
                storeFront: existingStoreFront,
                guid: guid
            )
        } catch let error as IPAError {
            // 如果需要验证码，直接抛出供 UI 处理
            if case .codeRequired = error {
                throw error
            }

            // 2. 自愈重试：若携带了旧 Cookie 且遭遇 403 / 401 / 网络鉴权拒绝，则丢弃过期 Cookie 以干净会话重试
            if !existingCookies.isEmpty {
                logger.warning("登录", "旧会话可能已过期失效 (\(error.localizedDescription))，正在自动丢弃旧 Cookie 并重建干净会话重试...")
                return try await executeAuthenticationFlow(
                    email: email,
                    password: password,
                    code: code,
                    cookies: [],
                    storeFront: existingStoreFront,
                    guid: guid
                )
            }

            throw error
        } catch {
            if !existingCookies.isEmpty {
                logger.warning("登录", "请求异常，正在自动清除缓存会话重试...")
                return try await executeAuthenticationFlow(
                    email: email,
                    password: password,
                    code: code,
                    cookies: [],
                    storeFront: existingStoreFront,
                    guid: guid
                )
            }
            throw error
        }
    }

    /// 刷新账号 Token（支持静默刷新或携带 2FA 验证码刷新）
    static func refreshToken(for account: Account, code: String = "") async throws -> Account {
        logger.info("登录", "正在刷新 Token: \(account.email)")
        return try await authenticate(
            email: account.email,
            password: account.password,
            code: code,
            existingCookies: account.cookies,
            existingStoreFront: account.storeFront
        )
    }

    // MARK: - 核心执行流程

    private static func executeAuthenticationFlow(
        email: String,
        password: String,
        code: String,
        cookies: [HTTPCookieData],
        storeFront: String,
        guid: String
    ) async throws -> Account {
        var currentCookies = cookies
        var activeStoreFront = storeFront
        let initialURL = await resolveAuthenticationURL(guid: guid)
        var currentURL = initialURL
        var redirectCount = 0
        let maxRedirects = 3
        var requestNumber = 1
        var lastError: Error?

        // Apple 会将初始地址重定向到账号所属 Pod；总请求次数限制为 4，避免重复提交凭据。
        while requestNumber <= 4, redirectCount <= maxRedirects {
            do {
                let requestAttempt = currentURL == initialURL ? requestNumber : 1
                let body: [String: Any] = [
                    "appleId": email,
                    "attempt": "\(requestAttempt)",
                    "guid": guid,
                    "password": "\(password)\(code.replacingOccurrences(of: " ", with: ""))",
                    "rmp": "0",
                    "why": "signIn"
                ]

                logger.info("登录", "正在进行 Apple SAP 安全认证 [\(currentURL.host ?? "未知服务器")]...")
                let (data, response, newCookies) = try await StoreClient.postPlist(
                    url: currentURL,
                    body: body,
                    cookies: currentCookies,
                    userAgentOverride: StoreClient.appleUserAgent,
                    contentType: "application/x-www-form-urlencoded",
                    signAction: true
                )
                mergeCookies(&currentCookies, with: newCookies)

                if let sfHeader = response.value(forHTTPHeaderField: "x-set-apple-store-front"),
                   let sf = sfHeader.components(separatedBy: "-").first,
                   !sf.isEmpty {
                    activeStoreFront = sf
                }

                if [301, 302, 303, 307, 308].contains(response.statusCode) {
                    guard let location = response.value(forHTTPHeaderField: "Location"),
                          let redirectURL = URL(string: location, relativeTo: currentURL)?.absoluteURL,
                          isAllowedAuthenticationURL(redirectURL) else {
                        throw IPAError.authenticationFailed("Apple 返回了不安全或无效的认证重定向地址")
                    }
                    redirectCount += 1
                    currentURL = normalizedAuthenticationURL(redirectURL, guid: guid)
                    logger.info("登录", "认证请求已分配至 Apple Store Pod: \(currentURL.host ?? "")")
                    requestNumber += 1
                    continue
                }

                guard !data.isEmpty else {
                    throw IPAError.authenticationFailed("Apple 登录响应为空 (HTTP \(response.statusCode))")
                }

                let dict: [String: Any]
                do {
                    dict = try PlistHelper.deserialize(data)
                } catch {
                    throw IPAError.authenticationFailed("Apple 返回非 plist 格式 (HTTP \(response.statusCode))")
                }

                let failureType = (dict["failureType"] as? String) ?? ""
                let customerMessage = (dict["customerMessage"] as? String) ?? ""

                // 首次返回通用凭据错误时，按 Apple 客户端行为更新 attempt 后再试一次。
                if requestNumber == 1, failureType == "-5000" {
                    requestNumber += 1
                    continue
                }

                if failureType.isEmpty,
                   (customerMessage == "MZFinance.BadLogin.Configurator_message" || customerMessage.contains("BadLogin")) {
                    logger.info("登录", code.isEmpty ? "Apple 要求提供双重验证码 (2FA)" : "Apple 未接受当前双重验证码")
                    throw IPAError.codeRequired
                }

                var failureMessage: String?
                if let dialog = dict["dialog"] as? [String: Any] {
                    failureMessage = (dialog["explanation"] as? String) ?? (dialog["message"] as? String)
                }
                if failureMessage == nil, !customerMessage.isEmpty {
                    failureMessage = customerMessage
                }

                if !failureType.isEmpty {
                    let invalidCredentialCodes = ["-5000", "1001", "5020"]
                    if invalidCredentialCodes.contains(failureType)
                        || customerMessage == "MZFinance.NoAccount_message" {
                        throw IPAError.authenticationFailed("Apple 账户不存在、密码错误或验证码无效")
                    }
                    throw IPAError.authenticationFailed(
                        failureMessage ?? "Apple 登录失败（错误码：\(failureType)）"
                    )
                }

                guard let accountInfo = dict["accountInfo"] as? [String: Any] else {
                    throw IPAError.authenticationFailed(failureMessage ?? "Apple 响应缺少账号信息")
                }
                let addressInfo = accountInfo["address"] as? [String: Any]

                guard let passwordToken = dict["passwordToken"] as? String,
                      !passwordToken.isEmpty,
                      let dsPersonId = stringValue(dict["dsPersonId"]),
                      !dsPersonId.isEmpty else {
                    throw IPAError.authenticationFailed(failureMessage ?? "Apple 响应缺少认证 Token")
                }

                let account = Account(
                    email: email,
                    password: password,
                    appleId: (accountInfo["appleId"] as? String) ?? email,
                    storeFront: activeStoreFront,
                    firstName: (addressInfo?["firstName"] as? String) ?? "",
                    lastName: (addressInfo?["lastName"] as? String) ?? "",
                    passwordToken: passwordToken,
                    directoryServicesId: dsPersonId,
                    cookies: currentCookies
                )

                logger.success("登录", "账号认证成功: \(account.displayName) [\(account.email)] (Store: \(account.storeFront))")
                return account
            } catch {
                lastError = error
                if case IPAError.codeRequired = error {
                    throw error
                }
                // 网络、签名及服务端拒绝均不应改地区或更换固定 Pod 后重复提交密码。
                throw error
            }
        }

        throw lastError ?? IPAError.authenticationFailed("认证失败，请检查账号密码或网络连接")
    }

    // MARK: - 动态端点解析与辅助方法

    private static func resolveAuthenticationURL(guid: String) async -> URL {
        if let dynamicURL = await fetchDynamicAuthURL(guid: guid) {
            logger.info("登录", "已从 Apple bag 获取认证端点: \(dynamicURL.host ?? "")")
            return dynamicURL
        }

        logger.warning("登录", "无法读取 Apple bag，回退到签名版兼容认证端点")
        return makeAuthURL(guid: guid)
    }

    private static func fetchDynamicAuthURL(guid: String) async -> URL? {
        guard let bagURL = URL(string: "https://init.itunes.apple.com/bag.xml?guid=\(guid)") else { return nil }
        var req = URLRequest(url: bagURL)
        req.setValue("application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
        req.setValue(StoreClient.appleUserAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 5

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
              let xmlString = String(data: data, encoding: .utf8) else {
            return nil
        }

        // 从返回的 XML 数据中提取嵌入的 plist
        if let start = xmlString.range(of: "<plist"),
           let end = xmlString.range(of: "</plist>", options: .backwards) {
            let plistStr = String(xmlString[start.lowerBound..<end.upperBound])
            if let pData = plistStr.data(using: .utf8),
               let dict = try? PropertyListSerialization.propertyList(from: pData, options: [], format: nil) as? [String: Any],
               let bag = dict["urlBag"] as? [String: Any] {
                // authorizeMachine 是设备授权接口，不能用来登录账号。
                for key in ["authenticateAccount", "configurator-authenticate-account"] {
                    if let authEndpoint = bag[key] as? String,
                       let endpointURL = URL(string: authEndpoint) {
                        let normalizedURL = normalizedAuthenticationURL(endpointURL, guid: guid)
                        if isAllowedAuthenticationURL(normalizedURL) {
                            return normalizedURL
                        }
                    }
                }
            }
        }
        return nil
    }

    private static func makeAuthURL(guid: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "buy.itunes.apple.com"
        components.path = "/WebObjects/MZFinance.woa/wa/authenticate"
        components.queryItems = [URLQueryItem(name: "guid", value: guid)]
        return components.url!
    }

    private static func normalizedAuthenticationURL(_ url: URL, guid: String) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        if components.path.contains("/native/") && !components.path.hasSuffix("/") {
            components.path += "/"
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "guid" }
        queryItems.append(URLQueryItem(name: "guid", value: guid))
        components.queryItems = queryItems
        return components.url ?? url
    }

    private static func isAllowedAuthenticationURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        let allowedHost = host == "buy.itunes.apple.com"
            || host == "auth.itunes.apple.com"
            || (host.hasPrefix("p") && host.hasSuffix("-buy.itunes.apple.com"))
        let allowedPath = url.path.contains("/authenticate") || url.path.contains("/auth/v1/")
        return allowedHost && allowedPath
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func mergeCookies(_ existing: inout [HTTPCookieData], with newCookies: [HTTPCookieData]) {
        for newCookie in newCookies {
            existing.removeAll { $0.name == newCookie.name && $0.domain == newCookie.domain }
            existing.append(newCookie)
        }
    }
}
