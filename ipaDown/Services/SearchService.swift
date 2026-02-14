//
//  SearchService.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// 设备类型
enum DeviceType: String, CaseIterable {
    case iPhone = "software"
    case iPad = "iPadSoftware"
    
    var displayName: String {
        switch self {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        }
    }
}

/// App 搜索服务
enum SearchService {
    private static let logger = AppLogger.shared
    
    /// 搜索 App
    static func search(
        term: String,
        countryCode: String = "CN",
        limit: Int = 10,
        deviceType: DeviceType = .iPhone
    ) async throws -> [AppSoftware] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "entity", value: deviceType.rawValue),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "media", value: "software"),
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: countryCode),
        ]
        
        guard let url = components.url else {
            throw IPAError.networkError("无效的搜索 URL")
        }
        
        logger.info("搜索", "搜索关键词: \(term) (商店国家/地区: \(countryCode))")
        
        let data = try await StoreClient.getJSON(url: url)
        
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        logger.success("搜索", "找到 \(response.resultCount) 个结果")
        return response.results
    }
    
    /// 通过 App ID 查找
    static func lookup(appId: Int64, countryCode: String = "CN") async throws -> AppSoftware {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        components.queryItems = [
            URLQueryItem(name: "id", value: "\(appId)"),
            URLQueryItem(name: "country", value: countryCode),
            URLQueryItem(name: "entity", value: "software,iPadSoftware"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "media", value: "software"),
        ]
        
        guard let url = components.url else {
            throw IPAError.networkError("无效的查找 URL")
        }
        
        logger.info("搜索", "查找 App ID: \(appId)")
        
        let data = try await StoreClient.getJSON(url: url)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        
        guard let app = response.results.first else {
            throw IPAError.invalidResponse("未找到 App ID: \(appId)")
        }
        
        logger.success("搜索", "找到: \(app.trackName)")
        return app
    }
    
    /// 通过 Bundle ID 查找
    static func lookupByBundleId(_ bundleId: String, countryCode: String = "CN") async throws -> AppSoftware {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleId),
            URLQueryItem(name: "country", value: countryCode),
            URLQueryItem(name: "entity", value: "software,iPadSoftware"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "media", value: "software"),
        ]
        
        guard let url = components.url else {
            throw IPAError.networkError("无效的查找 URL")
        }
        
        let data = try await StoreClient.getJSON(url: url)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        
        guard let app = response.results.first else {
            throw IPAError.invalidResponse("未找到 Bundle ID: \(bundleId)")
        }
        
        return app
    }
    
    /// 解析 App Store 链接或 ID
    static func parseInput(_ input: String, countryCode: String = "CN") async throws -> [AppSoftware] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 尝试解析为纯数字 App ID
        if let appId = Int64(trimmed) {
            let app = try await lookup(appId: appId, countryCode: countryCode)
            return [app]
        }
        
        // 尝试从 URL 中提取 App ID
        if let url = URL(string: trimmed),
           let appId = extractAppId(from: url) {
            let app = try await lookup(appId: appId, countryCode: countryCode)
            return [app]
        }
        
        // 当作搜索关键词处理
        return try await search(term: trimmed, countryCode: countryCode)
    }
    
    /// 从 App Store URL 中提取 App ID
    private static func extractAppId(from url: URL) -> Int64? {
        // https://apps.apple.com/cn/app/wechat/id414478124
        let path = url.path
        if let range = path.range(of: "/id") {
            let idString = String(path[range.upperBound...])
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .first ?? ""
            return Int64(idString)
        }
        
        // 查询参数中的 id
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let idItem = components.queryItems?.first(where: { $0.name == "id" }),
           let value = idItem.value {
            return Int64(value)
        }
        
        return nil
    }
    
    // MARK: - Private
    
    private struct SearchResponse: Codable {
        var resultCount: Int
        var results: [AppSoftware]
    }
}
