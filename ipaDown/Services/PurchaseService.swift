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
        if let failureType = dict["failureType"] as? String {
            switch failureType {
            case "2059":
                throw IPAError.purchaseFailed("暂时不可用 (temporarily unavailable)")
            case "2034":
                throw IPAError.tokenExpired
            case "5002", "2040":
                // 已在资料库中，视为成功
                logger.info("购买", "应用已在资料库中")
                return
            default:
                let msg = dict["customerMessage"] as? String ?? "购买失败: \(failureType)"
                throw IPAError.purchaseFailed(msg)
            }
        }
        
        // 检查购买成功
        if let docType = dict["jingleDocType"] as? String,
           let status = dict["status"] as? Int {
            if docType == "purchaseSuccess" && status == 0 {
                return
            }
        }
        
        // 判断是否成功（ipatool.js 模式）
        if let status = dict["status"] as? Int, status == 0 {
            return
        }
        
        throw IPAError.purchaseFailed("未知购买响应")
    }
}
