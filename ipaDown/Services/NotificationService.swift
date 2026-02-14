//
//  NotificationService.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation
import UserNotifications
import AppKit

/// 系统通知服务
class NotificationService {
    static let shared = NotificationService()
    
    private init() {}
    
    /// 请求通知权限
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                AppLogger.shared.success("系统", "已获得通知权限")
            } else if let error = error {
                AppLogger.shared.error("系统", "请求通知权限失败: \(error.localizedDescription)")
            } else {
                AppLogger.shared.warning("系统", "用户拒绝了通知权限")
            }
        }
    }
    
    /// 发送下载完成通知
    func sendDownloadCompleteNotification(for task: IPADownloadTask) {
        let content = UNMutableNotificationContent()
        content.title = "下载完成"
        content.subtitle = task.appName
        content.body = "版本 \(task.displayVersion) 已完成下载并签名成功。"
        content.sound = .default
        
        // 点击通知的操作（可以考虑打开下载目录，但 macOS 通知交互较复杂，暂时设为简单提醒）
        
        let request = UNNotificationRequest(
            identifier: "ipaDown.download.\(task.id.uuidString)",
            content: content,
            trigger: nil // 立即发送
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.shared.error("系统", "发送通知失败: \(error.localizedDescription)")
            }
        }
    }
}
