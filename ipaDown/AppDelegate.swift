//
//  AppDelegate.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import AppKit
import Sparkle

/// 应用代理，负责处理 Sparkle 更新及其他系统级事件
class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?
    
    // Sparkle 自动更新控制器
    let updaterController: SPUStandardUpdaterController
    
    override init() {
        // 初始化 Sparkle
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true, 
            updaterDelegate: nil, 
            userDriverDelegate: nil
        )
        super.init()
        Self.shared = self
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.shared.info("App", "ipaDown 启动成功")
        
        // 打印 Sparkle 配置状态
        if let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String {
            AppLogger.shared.info("Updater", "Feed URL: \(feedURL)")
        } else {
            AppLogger.shared.error("Updater", "未找到 SUFeedURL配置")
        }
        
        if let hasKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") {
            AppLogger.shared.info("Updater", "EdDSA 公钥已配置")
        } else {
            AppLogger.shared.error("Updater", "未找到 SUPublicEDKey 配置")
        }
    }
    
    /// 手动检查更新（带日志）
    func checkForUpdates() {
        AppLogger.shared.info("Updater", "用户触发检查更新...")
        if updaterController.updater.canCheckForUpdates {
            updaterController.checkForUpdates(nil)
            AppLogger.shared.info("Updater", "已调用 Sparkle checkForUpdates")
        } else {
            AppLogger.shared.error("Updater", "当前状态无法检查更新 (canCheckForUpdates = false)")
            // 尝试强制检查
            updaterController.checkForUpdates(nil)
        }
    }
}
