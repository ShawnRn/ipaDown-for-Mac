//
//  IPAError.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// 统一错误类型
enum IPAError: LocalizedError {
    case authenticationFailed(String)
    case codeRequired
    case networkError(String)
    case invalidResponse(String)
    case downloadFailed(String)
    case signatureFailed(String)
    case md5Mismatch(expected: String, actual: String)
    case licenseRequired
    case purchaseFailed(String)
    case accountNotFound
    case keychainError(String)
    case fileError(String)
    case tokenExpired
    
    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let msg): "认证失败: \(msg)"
        case .codeRequired: "需要两步验证码"
        case .networkError(let msg): "网络错误: \(msg)"
        case .invalidResponse(let msg): "无效响应: \(msg)"
        case .downloadFailed(let msg): "下载失败: \(msg)"
        case .signatureFailed(let msg): "签名失败: \(msg)"
        case .md5Mismatch(let expected, let actual): "MD5 校验失败: 预期 \(expected), 实际 \(actual)"
        case .licenseRequired: "未找到许可，请先购买此应用"
        case .purchaseFailed(let msg): "购买失败: \(msg)"
        case .accountNotFound: "账号未找到"
        case .keychainError(let msg): "Keychain 错误: \(msg)"
        case .fileError(let msg): "文件错误: \(msg)"
        case .tokenExpired: "密码 Token 已过期，请重新登录"
        }
    }
}
