//
//  SignatureService.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation
import ZIPFoundation

/// IPA 签名注入服务
nonisolated enum SignatureService {
    private static let logger = AppLogger.shared
    
    /// 签名 IPA 文件（注入 sinf 签名数据）
    static func signIPA(
        at ipaPath: URL,
        sinfs: [SinfData],
        metadata: [String: Any]? = nil
    ) async throws {
        // 捕获一个在 background context 下可调用的引用
        let logger = self.logger
        
        try await Task.detached(priority: .userInitiated) {
            logger.info("签名", "开始注入签名: \(ipaPath.lastPathComponent)")
            
            let archive = try Archive(url: ipaPath, accessMode: .update)
            
            // 1. 获取 Bundle 名称
            let bundleName = try readBundleName(from: archive)
            
            // 2. 注入 Sinf 签名
            if let manifest = try readManifestPlist(from: archive) {
                try injectFromManifest(manifest, into: archive, sinfs: sinfs, bundleName: bundleName)
            } else if let info = try readInfoPlist(from: archive) {
                try injectFromInfo(info, into: archive, sinfs: sinfs, bundleName: bundleName)
            } else {
                logger.warning("签名", "未能在包内找到 Manifest.plist 或 Info.plist，尝试默认路径注入")
                try injectToDefaultPath(into: archive, sinfs: sinfs, bundleName: bundleName)
            }
            
            // 3. 注入 iTunesMetadata.plist
            if let metadata = metadata {
                try injectMetadata(metadata, into: archive)
            }
            
            logger.success("签名", "签名数据注入完成: \(ipaPath.lastPathComponent)")
        }.value
    }
    
    // MARK: - 私有辅助方法
    
    private static func readBundleName(from archive: Archive) throws -> String {
        for entry in archive {
            if entry.path.contains(".app/Info.plist"), !entry.path.contains("/Watch/") {
                let components = entry.path.split(separator: "/")
                if let appFolder = components.first(where: { $0.hasSuffix(".app") }) {
                    return String(appFolder.replacingOccurrences(of: ".app", with: ""))
                }
            }
        }
        throw IPAError.signatureFailed("未能在 IPA 中定位到有效的 .app 目录")
    }
    
    private static func readManifestPlist(from archive: Archive) throws -> PackageManifest? {
        for entry in archive {
            if entry.path.hasSuffix(".app/SC_Info/Manifest.plist") {
                var data = Data()
                _ = try archive.extract(entry, consumer: { data.append($0) })
                return try PropertyListDecoder().decode(PackageManifest.self, from: data)
            }
        }
        return nil
    }
    
    private static func readInfoPlist(from archive: Archive) throws -> PackageInfo? {
        for entry in archive {
            if entry.path.hasSuffix(".app/Info.plist"), !entry.path.contains("/Watch/") {
                var data = Data()
                _ = try archive.extract(entry, consumer: { data.append($0) })
                // 允许失败，因为有些 Info.plist 可能是二进制格式导致 Decodable 失败
                if let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                   let executable = dict["CFBundleExecutable"] as? String {
                    return PackageInfo(bundleExecutable: executable)
                }
            }
        }
        return nil
    }
    
    private static func injectFromManifest(
        _ manifest: PackageManifest,
        into archive: Archive,
        sinfs: [SinfData],
        bundleName: String
    ) throws {
        for (index, sinfPath) in manifest.sinfPaths.enumerated() {
            guard index < sinfs.count else { break }
            let sinf = sinfs[index]
            let fullPath = "Payload/\(bundleName).app/\(sinfPath)"
            
            if archive[fullPath] != nil {
                try archive.remove(archive[fullPath]!)
            }
            
            try archive.addEntry(with: fullPath, type: .file, uncompressedSize: Int64(sinf.data.count), provider: { (position: Int64, size: Int) -> Data in
                return sinf.data.subdata(in: Int(position)..<Int(position) + size)
            })
        }
    }
    
    private static func injectFromInfo(
        _ info: PackageInfo,
        into archive: Archive,
        sinfs: [SinfData],
        bundleName: String
    ) throws {
        guard let sinf = sinfs.first else { return }
        let sinfPath = "Payload/\(bundleName).app/SC_Info/\(info.bundleExecutable).sinf"
        
        if archive[sinfPath] != nil {
            try archive.remove(archive[sinfPath]!)
        }
        
        try archive.addEntry(with: sinfPath, type: .file, uncompressedSize: Int64(sinf.data.count), provider: { (position: Int64, size: Int) -> Data in
            return sinf.data.subdata(in: Int(position)..<Int(position) + size)
        })
    }
    
    private static func injectToDefaultPath(
        into archive: Archive,
        sinfs: [SinfData],
        bundleName: String
    ) throws {
        guard let sinf = sinfs.first else { return }
        // 尝试推测路径，通常为 SC_Info 目录下同名文件
        let sinfPath = "Payload/\(bundleName).app/SC_Info/\(bundleName).sinf"
        
        if archive[sinfPath] != nil {
            try archive.remove(archive[sinfPath]!)
        }
        
        try archive.addEntry(with: sinfPath, type: .file, uncompressedSize: Int64(sinf.data.count), provider: { (position: Int64, size: Int) -> Data in
            return sinf.data.subdata(in: Int(position)..<Int(position) + size)
        })
    }
    
    private static func injectMetadata(_ metadata: [String: Any], into archive: Archive) throws {
        let metadataPath = "iTunesMetadata.plist"
        let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        
        if archive[metadataPath] != nil {
            try archive.remove(archive[metadataPath]!)
        }
        
        try archive.addEntry(with: metadataPath, type: .file, uncompressedSize: Int64(data.count), provider: { (position: Int64, size: Int) -> Data in
            return data.subdata(in: Int(position)..<Int(position) + size)
        })
    }
}

// MARK: - 模型定义

private struct PackageManifest: Decodable, Sendable {
    let sinfPaths: [String]
    
    enum CodingKeys: String, CodingKey {
        case sinfPaths = "SinfPaths"
    }
}

private struct PackageInfo: Sendable {
    let bundleExecutable: String
}
