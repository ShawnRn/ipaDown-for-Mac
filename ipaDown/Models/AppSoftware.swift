//
//  AppSoftware.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// App Store 搜索结果模型，与 iTunes Search API JSON 响应对齐
struct AppSoftware: Codable, Identifiable, Hashable, Equatable {
    var id: Int64 { trackId }
    
    var trackId: Int64
    var bundleId: String
    var trackName: String
    var version: String
    var price: Double?
    var artistName: String
    var sellerName: String?
    var description: String?
    var averageUserRating: Double?
    var userRatingCount: Int?
    var artworkUrl512: String?
    var artworkUrl100: String?
    var artworkUrl60: String?
    var screenshotUrls: [String]?
    var minimumOsVersion: String?
    var fileSizeBytes: String?
    var currentVersionReleaseDate: String?
    var releaseNotes: String?
    var formattedPrice: String?
    var primaryGenreName: String?
    
    /// 格式化文件大小
    var formattedSize: String {
        guard let bytes = fileSizeBytes, let size = Double(bytes) else { return "未知" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
    
    /// 最佳图标 URL
    var bestIconURL: URL? {
        let urlString = artworkUrl512 ?? artworkUrl100 ?? artworkUrl60
        return urlString.flatMap { URL(string: $0) }
    }
}
