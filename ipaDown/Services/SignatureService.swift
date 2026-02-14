//
//  SignatureService.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// IPA 签名注入服务
/// 要求 ipaDown.entitlements 中放开沙箱限制或使用 App Group 路径
enum SignatureService {
    private static let logger = AppLogger.shared
    
    /// 签名 IPA 文件（注入 sinf 签名数据）
    static func signIPA(
        at ipaPath: URL,
        sinfs: [SinfData],
        metadata: [String: Any]? = nil
    ) async throws {
        // Run on background thread to avoid blocking UI (Process.waitUntilExit is blocking)
        try await Task.detached(priority: .userInitiated) {
            await logger.info("签名", "开始签名: \(ipaPath.lastPathComponent)")
            
            // 由于在沙箱环境下，我们使用命令行工具来操作 zip
            // 用 /usr/bin/unzip 和 /usr/bin/zip 来代替直接的 zip 库操作
            
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("ipaDown_sign_\(UUID().uuidString)")
            
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }
            
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // 1. 解压 IPA
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", ipaPath.path, "-d", tempDir.path]
            unzipProcess.standardOutput = nil // Pipe() if we want logs, but nil for now to save memory
            unzipProcess.standardError = nil
            try unzipProcess.run()
            unzipProcess.waitUntilExit()
            
            guard unzipProcess.terminationStatus == 0 else {
                throw IPAError.signatureFailed("解压 IPA 失败")
            }
            
            // 2. 找到 .app 目录
            let payloadDir = tempDir.appendingPathComponent("Payload")
            let contents = try FileManager.default.contentsOfDirectory(
                at: payloadDir,
                includingPropertiesForKeys: nil
            )
            guard let appDir = contents.first(where: { $0.pathExtension == "app" }) else {
                throw IPAError.signatureFailed("未找到 .app 目录")
            }
            
            _ = appDir.deletingPathExtension().lastPathComponent
            
            // 3. 注入 sinf 签名
            let scInfoDir = appDir.appendingPathComponent("SC_Info")
            try FileManager.default.createDirectory(at: scInfoDir, withIntermediateDirectories: true)
            
            // 尝试读取 Manifest.plist
            let manifestPath = scInfoDir.appendingPathComponent("Manifest.plist")
            if FileManager.default.fileExists(atPath: manifestPath.path) {
                // 有 Manifest.plist，按路径注入
                let manifestData = try Data(contentsOf: manifestPath)
                if let manifest = try PropertyListSerialization.propertyList(from: manifestData, format: nil) as? [String: Any],
                   let sinfPaths = manifest["SinfPaths"] as? [String] {
                    for (index, sinfPath) in sinfPaths.enumerated() {
                        guard index < sinfs.count else { continue }
                        let fullPath = appDir.appendingPathComponent(sinfPath)
                        try FileManager.default.createDirectory(
                            at: fullPath.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try sinfs[index].data.write(to: fullPath)
                    }
                }
            } else {
                // 没有 Manifest，使用默认路径（BundleExecutable.sinf）
                let infoPlistPath = appDir.appendingPathComponent("Info.plist")
                if FileManager.default.fileExists(atPath: infoPlistPath.path) {
                    let infoData = try Data(contentsOf: infoPlistPath)
                    if let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
                       let bundleExecutable = info["CFBundleExecutable"] as? String,
                       let sinf = sinfs.first {
                        let sinfPath = scInfoDir.appendingPathComponent("\(bundleExecutable).sinf")
                        try sinf.data.write(to: sinfPath)
                    }
                }
            }
            
            // 4. 写入 iTunesMetadata.plist（如果有）
            if let metadata = metadata {
                // 如果是免更新任务，我们需要在这里处理 metadata
                // 但是 metadata 的“最新版本 ID”最好由外部传入或在 DownloadManager 中处理好
                // 现有的 metadata 已经是 DownloadService 返回的，如果是指定版本的，它包含的是历史 ID
                
                let metadataPath = tempDir.appendingPathComponent("Payload")
                    .deletingLastPathComponent()
                    .appendingPathComponent("iTunesMetadata.plist")
                let metadataData = try PropertyListSerialization.data(
                    fromPropertyList: metadata,
                    format: .xml,
                    options: 0
                )
                try metadataData.write(to: metadataPath)
            }
            
            // 5. 重新压缩为 IPA
            let signedPath = ipaPath.deletingLastPathComponent()
                .appendingPathComponent("signed_\(ipaPath.lastPathComponent)")
            
            let zipProcess = Process()
            zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            zipProcess.arguments = ["-r", signedPath.path, "Payload"]
            if metadata != nil {
                zipProcess.arguments?.append("iTunesMetadata.plist")
            }
            zipProcess.currentDirectoryURL = tempDir
            zipProcess.standardOutput = nil
            zipProcess.standardError = nil
            try zipProcess.run()
            zipProcess.waitUntilExit()
            
            guard zipProcess.terminationStatus == 0 else {
                throw IPAError.signatureFailed("重新压缩 IPA 失败")
            }
            
            // 6. 替换原文件
            try FileManager.default.removeItem(at: ipaPath)
            try FileManager.default.moveItem(at: signedPath, to: ipaPath)
            
            await logger.success("签名", "签名完成: \(ipaPath.lastPathComponent)")
        }.value
    }
}
