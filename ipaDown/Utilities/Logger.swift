//
//  Logger.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation
import os

/// 统一日志系统，同时支持 Console 和 UI 展示
@Observable
class AppLogger {
    static let shared = AppLogger()
    
    private let osLog = os.Logger(subsystem: "com.shawnrain.ipaDown", category: "App")
    
    /// 日志条目
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String
        let category: String
        
        enum Level: Int, Codable, CaseIterable {
            case debug = 0
            case info = 1
            case warning = 2
            case error = 3
            case success = 4
            
            var name: String {
                switch self {
                case .debug: "DEBUG"
                case .info: "INFO"
                case .warning: "WARN"
                case .error: "ERROR"
                case .success: "OK"
                }
            }
        }
        
        var formattedTime: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter.string(from: timestamp)
        }
        
        var displayText: String {
            "[\(formattedTime)] [\(level.name)] \(category): \(message)"
        }
    }
    
    var entries: [LogEntry] = []
    
    /// 当前显示的最低日志级别
    var minLevel: LogEntry.Level {
        get {
            let val = UserDefaults.standard.integer(forKey: "minLogLevel")
            return LogEntry.Level(rawValue: val) ?? .info
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "minLogLevel")
        }
    }
    
    private init() {}
    
    func log(_ level: LogEntry.Level, category: String, _ message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message, category: category)
        
        // OS Log 始终记录
        switch level {
        case .debug, .info, .success:
            osLog.info("[\(category)] \(message)")
        case .warning:
            osLog.warning("[\(category)] \(message)")
        case .error:
            osLog.error("[\(category)] \(message)")
        }
        
        // UI 列表根据级别过滤
        if level.rawValue >= minLevel.rawValue || level == .success {
            Task { @MainActor in
                self.entries.append(entry)
                // 保留最近 500 条
                if self.entries.count > 500 {
                    self.entries.removeFirst(self.entries.count - 500)
                }
            }
        }
    }
    
    func info(_ category: String, _ message: String) {
        log(.info, category: category, message)
    }
    
    func warning(_ category: String, _ message: String) {
        log(.warning, category: category, message)
    }
    
    func error(_ category: String, _ message: String) {
        log(.error, category: category, message)
    }
    
    func success(_ category: String, _ message: String) {
        log(.success, category: category, message)
    }
    
    func clear() {
        Task { @MainActor in
            entries.removeAll()
        }
    }
}
