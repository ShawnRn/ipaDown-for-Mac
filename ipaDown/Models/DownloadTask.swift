//
//  DownloadTask.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// 下载任务状态
enum DownloadStatus: String, Codable {
    case waiting = "waiting"
    case purchasing = "purchasing"
    case fetchingInfo = "fetchingInfo"
    case downloading = "downloading"
    case verifying = "verifying"
    case signing = "signing"
    case completed = "completed"
    case failed = "failed"
    case paused = "paused"
    
    var displayName: String {
        switch self {
        case .waiting: "等待中"
        case .purchasing: "购买中"
        case .fetchingInfo: "获取信息"
        case .downloading: "下载中"
        case .verifying: "校验中"
        case .signing: "签名中"
        case .completed: "已完成"
        case .failed: "失败"
        case .paused: "已暂停"
        }
    }
    
    var isActive: Bool {
        switch self {
        case .purchasing, .fetchingInfo, .downloading, .verifying, .signing:
            return true
        default:
            return false
        }
    }
}

/// 签名数据
struct SinfData: Codable, Hashable {
    var id: Int64
    var data: Data
}

/// 下载任务模型
@Observable
class IPADownloadTask: Identifiable, Codable {
    let id: UUID
    var appName: String
    var appId: Int64
    var bundleId: String
    var versionId: String
    var displayVersion: String
    var downloadURL: String?
    var sinfs: [SinfData]
    var status: DownloadStatus
    var progress: Double           // 0.0 ~ 1.0
    var speed: String              // e.g. "2.5 MB/s"
    var filePath: URL?
    var error: String?
    var iconURL: URL?
    var skipUpdate: Bool           // 免更新
    var md5: String?               // 预期 MD5
    var accountEmail: String       // 使用的账号
    var createdAt: Date
    var totalBytes: Int64 = 0
    
    /// Speed history for chart (last 60 points)
    var speedHistory: [Int64] = []
    
    var receivedBytes: Int64 = 0
    
    var sizeProgressString: String {
        let received = ByteCountFormatter.string(fromByteCount: receivedBytes, countStyle: .file)
        if totalBytes > 0 {
            let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "\(received) / \(total)"
        } else {
            return received
        }
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, appName, appId, bundleId, versionId, displayVersion, downloadURL, sinfs, status, progress, speed, filePath, error, iconURL, skipUpdate, md5, accountEmail, createdAt, totalBytes, receivedBytes
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        appName = try container.decode(String.self, forKey: .appName)
        appId = try container.decode(Int64.self, forKey: .appId)
        bundleId = try container.decode(String.self, forKey: .bundleId)
        versionId = try container.decode(String.self, forKey: .versionId)
        displayVersion = try container.decode(String.self, forKey: .displayVersion)
        downloadURL = try container.decodeIfPresent(String.self, forKey: .downloadURL)
        sinfs = try container.decode([SinfData].self, forKey: .sinfs)
        status = try container.decode(DownloadStatus.self, forKey: .status)
        progress = try container.decode(Double.self, forKey: .progress)
        speed = try container.decode(String.self, forKey: .speed)
        filePath = try container.decodeIfPresent(URL.self, forKey: .filePath)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        iconURL = try container.decodeIfPresent(URL.self, forKey: .iconURL)
        skipUpdate = try container.decode(Bool.self, forKey: .skipUpdate)
        md5 = try container.decodeIfPresent(String.self, forKey: .md5)
        accountEmail = try container.decode(String.self, forKey: .accountEmail)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        totalBytes = try container.decode(Int64.self, forKey: .totalBytes)
        receivedBytes = try container.decode(Int64.self, forKey: .receivedBytes)
        
        // 恢复后状态调整
        if status.isActive || status == .waiting {
            status = .waiting // 重启后进行中的任务改为等待中
            speed = "等待恢复"
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(appName, forKey: .appName)
        try container.encode(appId, forKey: .appId)
        try container.encode(bundleId, forKey: .bundleId)
        try container.encode(versionId, forKey: .versionId)
        try container.encode(displayVersion, forKey: .displayVersion)
        try container.encode(downloadURL, forKey: .downloadURL)
        try container.encode(sinfs, forKey: .sinfs)
        try container.encode(status, forKey: .status)
        try container.encode(progress, forKey: .progress)
        try container.encode(speed, forKey: .speed)
        try container.encode(filePath, forKey: .filePath)
        try container.encode(error, forKey: .error)
        try container.encode(iconURL, forKey: .iconURL)
        try container.encode(skipUpdate, forKey: .skipUpdate)
        try container.encode(md5, forKey: .md5)
        try container.encode(accountEmail, forKey: .accountEmail)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encode(receivedBytes, forKey: .receivedBytes)
    }
    
    init(
        appName: String,
        appId: Int64,
        bundleId: String,
        versionId: String = "",
        displayVersion: String = "",
        accountEmail: String,
        skipUpdate: Bool = false,
        iconURL: URL? = nil
    ) {
        self.id = UUID()
        self.appName = appName
        self.appId = appId
        self.bundleId = bundleId
        self.versionId = versionId
        self.displayVersion = displayVersion
        self.downloadURL = nil
        self.sinfs = []
        self.status = .waiting
        self.progress = 0
        self.speed = ""
        self.filePath = nil
        self.error = nil
        self.iconURL = iconURL
        self.skipUpdate = skipUpdate
        self.md5 = nil
        self.accountEmail = accountEmail
        self.createdAt = Date()
    }
    
    var fileName: String {
        "\(appName)_\(displayVersion.isEmpty ? "unknown" : displayVersion).ipa"
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}
