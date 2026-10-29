//
//  PurchaseService.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// Apple Store 应用购买服务
enum PurchaseService {
    private static let logger = AppLogger.shared
    
    /// 购买（获取许可）免费应用
    static func purchase(account: inout Account, appId: Int64, versionId: String = "0") async throws {
        let guid = DeviceIdentifier.getOrCreate()
        
        logger.info("购买", "正在获取许可: App ID \(appId)")
        
        // 首先尝试 STDQ
        do {
            try await purchaseWithParams(
                account: &account,
                appId: appId,
                versionId: versionId,
                guid: guid,
                pricingParameters: "STDQ"
            )
        } catch let error as IPAError {
            // 如果提示暂时不可用，尝试 GAME 参数
            if case .purchaseFailed(let msg) = error,
               msg.contains("temporarily unavailable") || msg.contains("暂时不可用") {
                logger.info("购买", "STDQ 不可用，尝试 GAME 参数")
                try await purchaseWithParams(
                    account: &account,
                    appId: appId,
                    versionId: versionId,
                    guid: guid,
                    pricingParameters: "GAME"
                )
            } else {
                throw error
            }
        }
        
        logger.success("购买", "获取许可成功")
    }
    
    private static func purchaseWithParams(
        account: inout Account,
        appId: Int64,
        versionId: String,
        guid: String,
        pricingParameters: String
    ) async throws {
        let url = URL(string: "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/buyProduct")!
        
        let body: [String: Any] = [
            "appExtVrsId": versionId,
            "hasAskedToFulfillPreorder": "true",
            "buyWithoutAuthorization": "true",
            "hasDoneAgeCheck": "true",
            "guid": guid,
            "needDiv": "0",
            "origPage": "Software-\(appId)",
            "origPageLocation": "Buy",
            "price": "0",
            "pricingParameters": pricingParameters,
            "productType": "C",
            "salableAdamId": appId,
        ]
        
        var headers = StoreClient.authHeaders(for: account)
        headers["X-Token"] = account.passwordToken
        
        let (data, _, newCookies) = try await StoreClient.postPlist(
            url: url,
            body: body,
            headers: headers,
            cookies: account.cookies,
            userAgentOverride: StoreClient.appleUserAgent
        )
        
        // 合并 cookies
        for cookie in newCookies {
            account.cookies.removeAll { $0.name == cookie.name && $0.domain == cookie.domain }
            account.cookies.append(cookie)
        }
        
        let dict = try PlistHelper.deserialize(data)
        
        // 检查失败类型
        let customerMsg = PlistHelper.responseMessage(in: dict)
        if let failureType = PlistHelper.stringValue(dict["failureType"]) {
            switch failureType {
            case "2059":
                throw IPAError.purchaseFailed("暂时不可用 (temporarily unavailable)")
            case "1008", "2002", "2034", "2042":
                throw IPAError.tokenExpired
            case "5002", "2040":
                // buyProduct 的 5002 表示许可已存在，不是 Token 过期。
                // 下载接口中的同码含义不同，不能共用错误码分类。
                logger.info("购买", "应用已在资料库中")
                return
            default:
                let msg = customerMsg ?? "购买失败: \(failureType)"
                if msg.localizedCaseInsensitiveContains("password has changed")
                    || msg.localizedCaseInsensitiveContains("sign in")
                    || msg.localizedCaseInsensitiveContains("session") {
                    throw IPAError.tokenExpired
                }
                throw IPAError.purchaseFailed(msg)
            }
        }
        
        // 检查购买成功
        if let docType = dict["jingleDocType"] as? String,
           let status = PlistHelper.intValue(dict["status"]) {
            if docType == "purchaseSuccess" && status == 0 {
                return
            }
        }
        
        // 判断是否成功（ipatool.js 模式）
        if let status = PlistHelper.intValue(dict["status"]), status == 0 {
            return
        }

        if let message = PlistHelper.responseMessage(in: dict) {
            throw IPAError.purchaseFailed(message)
        }

        let status = PlistHelper.stringValue(dict["status"])
        throw IPAError.purchaseFailed(status.map { "Apple 返回未知购买响应（状态 \($0)）" } ?? "Apple 返回未知购买响应")
    }
}
