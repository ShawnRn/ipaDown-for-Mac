//
//  LockedValue.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// 线程安全的值封装
public final class LockedValue<T: Sendable>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    
    public init(_ value: T) {
        self.value = value
    }
    
    public func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
