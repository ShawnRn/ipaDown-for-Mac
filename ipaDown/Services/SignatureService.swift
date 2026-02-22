//
//  SignatureService.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// IPA 签名注入服务
enum SignatureService {
    private static let logger = AppLogger.shared
    
    /// 签名 IPA 文件（注入 sinf 签名数据）
    static func signIPA(
        at ipaPath: URL,
        sinfs: [SinfData],
        metadata: [String: Any]? = nil
    ) async throws {
        #if os(macOS)
        // macOS: 使用 Process 调用 unzip/zip 进行签名注入
        try await Task.detached(priority: .userInitiated) {
            await logger.info("签名", "开始签名: \(ipaPath.lastPathComponent)")
            
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
            unzipProcess.standardOutput = nil
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
            
            let manifestPath = scInfoDir.appendingPathComponent("Manifest.plist")
            if FileManager.default.fileExists(atPath: manifestPath.path) {
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
        #else
        // iOS: 不支持 Process，跳过签名步骤
        logger.warning("签名", "iOS 平台不支持 IPA 签名注入，已跳过: \(ipaPath.lastPathComponent)")
        #endif
    }
}
