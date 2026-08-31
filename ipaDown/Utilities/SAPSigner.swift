//
//  SAPSigner.swift
//  ipaDown
//

import Foundation

/// Apple Store SAP 请求签名封装。
enum SAPSigner {
    static func sign(_ data: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            var error: NSError?
            guard let signature = IPACommerceKitCreateSAPSignature(data, &error) else {
                let detail = error?.localizedDescription ?? "当前系统无法生成 Apple SAP 请求签名"
                throw IPAError.authenticationFailed(
                    "无法完成 Apple 新版安全认证：\(detail)"
                )
            }
            return signature
        }.value
    }
}
