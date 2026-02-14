//
//  MD5Helper.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import CryptoKit
import Foundation

/// MD5 校验辅助工具
enum MD5Helper {
    /// 计算文件 MD5（流式读取，支持大文件）
    static func calculateMD5(of fileURL: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handle = try FileHandle(forReadingFrom: fileURL)
                    defer { handle.closeFile() }
                    
                    var hasher = Insecure.MD5()
                    let bufferSize = 1024 * 1024 // 1MB chunks
                    
                    while autoreleasepool(invoking: {
                        let data = handle.readData(ofLength: bufferSize)
                        guard !data.isEmpty else { return false }
                        hasher.update(data: data)
                        return true
                    }) {}
                    
                    let digest = hasher.finalize()
                    let md5String = digest.map { String(format: "%02hhx", $0) }.joined()
                    continuation.resume(returning: md5String)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// 计算字符串 MD5
    static func md5(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
