//
//  VersionService.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// 版本查询服务
enum VersionService {
    private static let logger = AppLogger.shared
    
    /// 查询应用的所有历史版本 ID 列表
    static func listVersionIds(
        account: Account,
        appId: Int64
    ) async throws -> [String] {
        logger.info("版本", "正在查询历史版本: App ID \(appId)")
        
        let guid = DeviceIdentifier.getOrCreate()
        
        let url = URL(string: "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct")!
        
        let body: [String: Any] = [
            "creditDisplay": "",
            "guid": guid,
            "adamId": appId,
        ]
        
        var headers = StoreClient.authHeaders(for: account)
        headers["X-Token"] = account.passwordToken
        
        let (data, _, _) = try await StoreClient.postPlist(
            url: url,
            body: body,
            headers: headers,
            cookies: account.cookies,
            userAgentOverride: StoreClient.appleUserAgent
        )
        
        let dict = try PlistHelper.deserialize(data)
        
        // 调试日志
        logger.info("版本", "响应 keys: \(dict.keys.sorted().joined(separator: ", "))")
        
        // 检查失败
        if let failureType = dict["failureType"] as? String {
            logger.info("版本", "failureType: \(failureType), customerMessage: \(dict["customerMessage"] as? String ?? "无")")
            if failureType == "2034" {
                throw IPAError.tokenExpired
            }
            if failureType == "1008" || failureType == "9610" {
                throw IPAError.licenseRequired
            }
            let msg = dict["customerMessage"] as? String ?? "版本查询失败: \(failureType)"
            throw IPAError.downloadFailed(msg)
        }
        
        // 从 songList 中提取 softwareVersionExternalIdentifiers
        guard let items = dict["songList"] as? [[String: Any]],
              let item = items.first else {
            logger.info("版本", "songList 为空或不存在")
            throw IPAError.invalidResponse("未找到版本信息")
        }
        
        logger.info("版本", "songList item keys: \(item.keys.sorted().joined(separator: ", "))")
        
        var versionIds: [String] = []
        
        // 尝试从 metadata 中获取
        if let metadata = item["metadata"] as? [String: Any],
           let ids = metadata["softwareVersionExternalIdentifiers"] as? [Any] {
            versionIds = ids.map { "\($0)" }
            logger.info("版本", "从 metadata 找到 \(versionIds.count) 个版本")
        } else if let ids = item["softwareVersionExternalIdentifiers"] as? [Any] {
            versionIds = ids.map { "\($0)" }
            logger.info("版本", "从 item 找到 \(versionIds.count) 个版本")
        } else {
            logger.info("版本", "未找到 softwareVersionExternalIdentifiers")
            if let metadata = item["metadata"] as? [String: Any] {
                logger.info("版本", "metadata keys: \(metadata.keys.sorted().joined(separator: ", "))")
            }
        }
        
        // 反转，使最新在前
        versionIds.reverse()
        
        logger.success("版本", "找到 \(versionIds.count) 个历史版本")
        return versionIds
    }
    
    /// 查询指定版本的详细信息（版本号 + 日期）
    static func getVersionMetadata(
        account: Account,
        appId: Int64,
        versionId: String
    ) async throws -> VersionInfo {
        let guid = DeviceIdentifier.getOrCreate()
        
        let url = URL(string: "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct")!
        
        let body: [String: Any] = [
            "creditDisplay": "",
            "guid": guid,
            "salableAdamId": appId,
            "externalVersionId": versionId,
        ]
        
        // 严格参考 Asspp 实现，不发送 X-Token 和 X-Apple-Store-Front
        // 发送这些额外 Header 可能导致服务器返回当前版本的元数据而非历史版本
        let headers: [String: String] = [
            "User-Agent": StoreClient.appleUserAgent,
            "X-Dsid": account.directoryServicesId,
            "iCloud-DSID": account.directoryServicesId,
        ]
        
        let (data, _, _) = try await StoreClient.postPlist(
            url: url,
            body: body,
            headers: headers,
            cookies: account.cookies,
            userAgentOverride: StoreClient.appleUserAgent
        )
        
        let dict = try PlistHelper.deserialize(data)
        
        // 提取版本元数据
        guard let items = dict["songList"] as? [[String: Any]],
              let item = items.first else {
            return VersionInfo(externalVersionId: versionId)
        }
        
        let metadata = item["metadata"] as? [String: Any]
        let bundleShortVersion = metadata?["bundleShortVersionString"] as? String
        
        // 尝试多个可能的日期字段
        // releaseDate 往往是 App 首次发布日期
        // currentVersionReleaseDate 可能是当前版本日期
        let dateKeys = ["currentVersionReleaseDate", "versionDate", "releaseDate", "date"]
        var releaseDateStr: String?
        
        for key in dateKeys {
            if let date = metadata?[key] as? String {
                releaseDateStr = date
                break
            }
        }
        
        var date: Date?
        if let dateStr = releaseDateStr {
            let formatter = ISO8601DateFormatter()
            date = formatter.date(from: dateStr)
            if date == nil {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ" // 再次尝试带时区的标准格式
                date = df.date(from: dateStr)
            }
            if date == nil {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                date = df.date(from: dateStr)
            }
        }
        
        // 调试：打印 metadata keys 和值，寻找正确的日期字段
        // 只打印第一个版本的，避免刷屏
        if versionId == "882155323" || Int.random(in: 0...20) == 0 {
             logger.info("版本", "metadata for \(versionId): \(metadata?.keys.sorted().joined(separator: ", ") ?? "nil")")
             if let metadata = metadata {
                 logger.info("版本", "releaseDate: \(metadata["releaseDate"] as? String ?? "nil")")
                 // 打印所有可能包含日期的字段
                 for (key, value) in metadata {
                     if key.lowercased().contains("date") || key.lowercased().contains("time") {
                        logger.info("版本", "Possible date: \(key) = \(value)")
                     }
                 }
             }
        }
        
        return VersionInfo(
            externalVersionId: versionId,
            displayVersion: bundleShortVersion,
            releaseDate: date
        )
    }
    
    /// 批量查询版本详情
    static func batchGetVersionMetadata(
        account: Account,
        appId: Int64,
        versionIds: [String],
        maxConcurrent: Int = 3
    ) -> AsyncStream<(String, VersionInfo?)> {
        AsyncStream { continuation in
            Task {
                await withTaskGroup(of: (String, VersionInfo?).self) { group in
                    var pending = versionIds.makeIterator()
                    var active = 0
                    
                    // 启动初始批次
                    for _ in 0..<min(maxConcurrent, versionIds.count) {
                        if let vid = pending.next() {
                            active += 1
                            group.addTask {
                                let info = try? await getVersionMetadata(
                                    account: account,
                                    appId: appId,
                                    versionId: vid
                                )
                                return (vid, info)
                            }
                        }
                    }
                    
                    for await result in group {
                        continuation.yield(result)
                        
                        if let vid = pending.next() {
                            group.addTask {
                                let info = try? await getVersionMetadata(
                                    account: account,
                                    appId: appId,
                                    versionId: vid
                                )
                                return (vid, info)
                            }
                        }
                    }
                }
                
                continuation.finish()
            }
        }
    }
    
    // MARK: - Bilin API (Third Party)
    
    private struct BilinResponse: Codable {
        let code: Int?
        let data: [BilinVersionItem]?
        let total: Int?
    }
    
    private struct BilinVersionItem: Codable {
        let bundle_version: String
        let external_identifier: Int64
        let created_at: String // Format: 2026-02-08 01:32:05
    }
    
    /// 从 Bilin API 获取指定页的历史版本
    /// - Returns: (versions, hasMore)
    static func getVersionHistoryFromBilin(appId: Int64, page: Int) async throws -> ([VersionInfo], Bool) {
        logger.info("版本", "正在通过 Bilin API 查询历史版本 (第 \(page) 页): App ID \(appId)")
        
        let baseUrl = "https://apis.bilin.eu.org/history/"
        var pageVersions: [VersionInfo] = []
        var hasMore = false
        
        // 假设服务器返回的是北京时间或者 UTC
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let urlString = "\(baseUrl)\(appId)?page=\(page)"
        guard let url = URL(string: urlString) else { return ([], false) }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            logger.error("版本", "Bilin API 请求失败: \(page)")
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let resp = try decoder.decode(BilinResponse.self, from: data)
        
        if let items = resp.data, !items.isEmpty {
            for item in items {
                let date = formatter.date(from: item.created_at)
                let info = VersionInfo(
                    externalVersionId: String(item.external_identifier),
                    displayVersion: item.bundle_version,
                    releaseDate: date
                )
                pageVersions.append(info)
            }
            logger.info("版本", "Bilin API 第 \(page) 页: 获取到 \(items.count) 个版本")
            
            // 如果返回 10 条，可能还有下一页
            // 严谨判断：resp.total 是否存在？
            if let _ = resp.total {
                // 当前已获取数量 vs 总数？ API 似乎是分页的
                // 简单判断: 如果 items.count < 10，则肯定没下一页
                hasMore = items.count >= 10
            } else {
                 hasMore = items.count >= 10
            }
        } else {
            logger.info("版本", "Bilin API 第 \(page) 页: 无数据")
            hasMore = false
        }
        
        return (pageVersions, hasMore)
    }
}
