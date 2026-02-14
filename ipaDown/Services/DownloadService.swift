//
//  DownloadService.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation
import os

/// 下载信息
struct DownloadInfo {
    var downloadURL: String
    var sinfs: [SinfData]
    var md5: String?
    var metadata: [String: Any]?
}

/// Apple Store IPA 下载服务
enum DownloadService {
    private static let logger = AppLogger.shared
    
    // MARK: - 获取下载 URL
    
    /// 获取下载 URL 和签名数据
    static func requestDownload(
        account: Account,
        appId: Int64,
        versionId: String = ""
    ) async throws -> DownloadInfo {
        let guid = DeviceIdentifier.getOrCreate()
        
        logger.info("下载", "正在获取下载信息: App ID \(appId)")
        
        let url = URL(string: "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct")!
        
        var body: [String: Any] = [
            "creditDisplay": "",
            "guid": guid,
            "adamId": appId,
            "salableAdamId": appId, // 同时包含两者以确保兼容性
        ]
        
        // 指定版本
        if !versionId.isEmpty {
            if let vid = Int64(versionId) {
                body["externalVersionId"] = vid
            }
        }
        
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
        
        // 检查失败
        if let failureType = dict["failureType"] as? String {
            switch failureType {
            case "2034":
                throw IPAError.tokenExpired
            case "1008":
                throw IPAError.licenseRequired
            default:
                let msg = dict["customerMessage"] as? String ?? "下载请求失败: \(failureType)"
                throw IPAError.downloadFailed(msg)
            }
        }
        
        // 提取下载信息
        guard let items = dict["songList"] as? [[String: Any]],
              let item = items.first else {
            throw IPAError.downloadFailed("未找到下载项")
        }
        
        guard let downloadURL = item["URL"] as? String else {
            throw IPAError.downloadFailed("未找到下载 URL")
        }
        
        let md5 = item["md5"] as? String
        let metadata = item["metadata"] as? [String: Any]
        
        // 提取 sinf 签名数据
        var sinfs: [SinfData] = []
        if let sinfDicts = item["sinfs"] as? [[String: Any]] {
            for sinfDict in sinfDicts {
                if let id = sinfDict["id"] as? Int64,
                   let sinfData = sinfDict["sinf"] as? Data {
                    sinfs.append(SinfData(id: id, data: sinfData))
                }
            }
        }
        
        logger.success("下载", "获取下载链接成功")
        
        return DownloadInfo(
            downloadURL: downloadURL,
            sinfs: sinfs,
            md5: md5,
            metadata: metadata
        )
    }
    
    // MARK: - 分块下载
    
    /// 下载文件（分块 + 多线程）
    static func downloadFile(
        from urlString: String,
        to destination: URL,
        progress: @escaping @Sendable (Double, String, Int64, Int64, Int64) -> Void
    ) async throws {
        guard let url = URL(string: urlString) else {
            throw IPAError.downloadFailed("无效的下载 URL")
        }
        
        logger.info("下载", "开始下载到: \(destination.lastPathComponent)")
        
        // 获取文件大小
        let fileSize = try await getFileSize(url: url)
        
        if fileSize > 0 {
            // 大文件：分块下载
            try await chunkedDownload(
                url: url,
                fileSize: fileSize,
                destination: destination,
                progress: progress
            )
        } else {
            // 无法获取大小：直接下载
            try await simpleDownload(url: url, destination: destination, progress: progress)
        }
        
        logger.success("下载", "文件下载完成")
    }
    
    // MARK: - Private
    
    private static func getFileSize(url: URL) async throws -> Int64 {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, resp) = try await URLSession.shared.data(for: request)
        guard let httpResp = resp as? HTTPURLResponse else { return 0 }
        return Int64(httpResp.value(forHTTPHeaderField: "Content-Length") ?? "0") ?? 0
    }
    
    private static func chunkedDownload(
        url: URL,
        fileSize: Int64,
        destination: URL,
        progress: @escaping @Sendable (Double, String, Int64, Int64, Int64) -> Void
    ) async throws {
        let chunkSize: Int64 = 5 * 1024 * 1024  // 5MB per chunk
        let maxConcurrent = 10
        let chunkCount = Int((fileSize + chunkSize - 1) / chunkSize)
        
        // 创建目标文件
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ipaDown_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let downloadedBytes = AtomicCounter()
        let startTime = Date()
        
        // 分块下载
        try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            var activeTasks = 0
            var chunkIndex = 0
            var results: [(Int, URL)] = []
            
            while chunkIndex < chunkCount || activeTasks > 0 {
                // 添加新任务
                while activeTasks < maxConcurrent && chunkIndex < chunkCount {
                    let index = chunkIndex
                    let start = Int64(index) * chunkSize
                    let end = min(start + chunkSize - 1, fileSize - 1)
                    let chunkFile = tempDir.appendingPathComponent("chunk_\(index)")
                    
                    group.addTask {
                        try Task.checkCancellation()
                        try await downloadChunk(url: url, start: start, end: end, to: chunkFile)
                        try Task.checkCancellation()
                        let bytes = await downloadedBytes.add(end - start + 1)
                        let pct = Double(bytes) / Double(fileSize)
                        let elapsed = Date().timeIntervalSince(startTime)
                        let speed = elapsed > 0 ? Double(bytes) / elapsed : 0
                        let speedStr = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s"
                        progress(pct, speedStr, Int64(speed), bytes, fileSize)
                        return (index, chunkFile)
                    }
                    activeTasks += 1
                    chunkIndex += 1
                }
                
                // 等待一个完成
                if let result = try await group.next() {
                    try Task.checkCancellation()
                    results.append(result)
                    activeTasks -= 1
                }
            }
            
            try Task.checkCancellation()
            
            // 合并分块 (在后台线程执行，避免阻塞 UI)
            logger.info("下载", "开始合并分块...")
            let mergeStart = Date()
            
            try await Task.detached(priority: .utility) {
                // 排序
                let sortedResults = results.sorted { $0.0 < $1.0 }
                
                // 创建/覆盖目标文件
                if !FileManager.default.createFile(atPath: destination.path, contents: nil) {
                    throw IPAError.downloadFailed("无法创建目标文件")
                }
                
                let fileHandle = try FileHandle(forWritingTo: destination)
                defer { try? fileHandle.close() }
                
                // 逐个写入
                for (_, chunkFile) in sortedResults {
                    // 使用 autoreleasepool 降低内存峰值
                    try autoreleasepool {
                        let chunkData = try Data(contentsOf: chunkFile)
                        fileHandle.write(chunkData)
                    }
                    // 删除已合并的分块文件
                    try? FileManager.default.removeItem(at: chunkFile)
                }
            }.value
            
            let mergeTime = Date().timeIntervalSince(mergeStart)
            logger.info("下载", "合并完成，耗时: \(String(format: "%.2f", mergeTime))s")
        }
        
        // 清理临时目录
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    private static func downloadChunk(
        url: URL,
        start: Int64,
        end: Int64,
        to destination: URL,
        retries: Int = 3
    ) async throws {
        var lastError: Error?
        
        for attempt in 0..<retries {
            do {
                var request = URLRequest(url: url)
                request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                request.timeoutInterval = 60
                
                let (data, _) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                try data.write(to: destination)
                return
            } catch {
                lastError = error
                if attempt < retries - 1 {
                    try await Task.sleep(for: .seconds(1))
                }
            }
        }
        
        throw lastError ?? IPAError.downloadFailed("分块下载失败")
    }
    
    private static func simpleDownload(
        url: URL,
        destination: URL,
        progress: @escaping @Sendable (Double, String, Int64, Int64, Int64) -> Void
    ) async throws {
        let (localURL, _) = try await URLSession.shared.download(from: url)
        let attr = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let fileSize = attr[.size] as? Int64 ?? 0
        try FileManager.default.moveItem(at: localURL, to: destination)
        progress(1.0, "", 0, fileSize, fileSize)
    }
}

private actor AtomicCounter {
    var value: Int64 = 0
    func add(_ amount: Int64) -> Int64 {
        value += amount
        return value
    }
}


