//
//  PlistHelper.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// Plist 序列化辅助工具
enum PlistHelper {
    /// 将字典序列化为 XML plist Data
    static func serialize(_ dictionary: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )
    }
    
    /// 将 Data 反序列化为字典
    static func deserialize(_ data: Data) throws -> [String: Any] {
        let result = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        guard let dict = result as? [String: Any] else {
            throw IPAError.invalidResponse("响应格式不是字典")
        }
        return dict
    }

    /// Apple 的 plist 接口会在不同响应中把错误码编码为 string 或 integer。
    /// 统一转换后，调用方不会因为类型变化漏掉真实错误。
    static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    /// 提取 Apple 响应中常见的用户可读错误信息，包括嵌套的 dialog。
    static func responseMessage(in dictionary: [String: Any]) -> String? {
        let messageKeys = ["customerMessage", "failureMessage", "localizedMessage", "message", "reason"]
        for key in messageKeys {
            if let message = stringValue(dictionary[key]), !message.isEmpty {
                return message
            }
        }

        if let dialog = dictionary["dialog"] as? [String: Any] {
            for key in ["message", "explanation", "title"] {
                if let message = stringValue(dialog[key]), !message.isEmpty {
                    return message
                }
            }
        }

        return nil
    }
}
