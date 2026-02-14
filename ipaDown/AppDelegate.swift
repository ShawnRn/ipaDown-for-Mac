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
    }
}
