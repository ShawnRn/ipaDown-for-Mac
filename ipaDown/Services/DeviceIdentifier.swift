//
//  DeviceIdentifier.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation
import IOKit

/// 获取 macOS 设备标识符（MAC 地址）
enum DeviceIdentifier {
    /// 获取系统网卡 MAC 地址并格式化为 GUID
    static func system() -> String? {
        guard let macAddress = getMACAddress() else { return nil }
        return macAddress
            .uppercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
    
    /// 生成随机设备标识符
    static func random() -> String {
        (0..<6).map { _ in String(format: "%02X", Int.random(in: 0...255)) }.joined()
    }
    
    /// 获取主网卡 MAC 地址
    private static func getMACAddress() -> String? {
        let matchingDict = IOServiceMatching("IOEthernetInterface") as NSMutableDictionary
        
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            
            // 获取父服务
            var parentService: io_object_t = 0
            guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parentService) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(parentService) }
            
            // 获取 MAC 地址
            if let macData = IORegistryEntryCreateCFProperty(
                parentService,
                "IOMACAddress" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? Data {
                let mac = macData.map { String(format: "%02X", $0) }.joined(separator: ":")
                return mac
            }
        }
        
        return nil
    }
    
    /// 获取或生成持久化的设备标识符
    static func getOrCreate() -> String {
        let key = "DeviceIdentifier"
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
            return saved
        }
        let id = system() ?? random()
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
