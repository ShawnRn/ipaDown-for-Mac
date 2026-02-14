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
}
