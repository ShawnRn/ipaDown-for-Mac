//
//  ipaDownApp.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import SwiftUI
#if os(macOS)
import Sparkle
#endif

@main
struct ipaDownApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @AppStorage("theme") private var theme = "auto"
    @State private var accountManager = AccountManager()
    @State private var searchManager = SearchManager()
    @State private var versionManager = VersionManager()
    @State private var downloadManager = DownloadManager()
    @State private var navigationManager = NavigationManager()
    
    init() {
        // 初始化设备标识符
        _ = DeviceIdentifier.getOrCreate()
        // 请求通知权限
        NotificationService.shared.requestPermission()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(accountManager)
                .environment(searchManager)
                .environment(versionManager)
                .environment(downloadManager)
                .environment(navigationManager)
                .preferredColorScheme(theme == "light" ? .light : (theme == "dark" ? .dark : nil))
                .id(theme) // 强制视图树重建以重新评估环境值
                #if os(macOS)
                .onAppear {
                    applyTheme(theme)
                }
                .onChange(of: theme) { _, newValue in
                    applyTheme(newValue)
                }
                #endif
                .task {
                    // 启动时关联管理器并刷新 Token
                    downloadManager.accountManager = accountManager
                    await accountManager.refreshAllTokens()
                }
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置...") {
                    // 现有逻辑暂保留，未来可添加通知
                }
                .keyboardShortcut(",", modifiers: .command)
                
                Divider()
                
                Button("检查更新...") {
                    if let delegate = NSApplication.shared.delegate as? AppDelegate {
                        delegate.updaterController.checkForUpdates(nil)
                    }
                }
            }
        }
        #endif
    }
    
    #if os(macOS)
    private func applyTheme(_ theme: String) {
        DispatchQueue.main.async {
            switch theme {
            case "dark":
                NSApp.appearance = NSAppearance(named: .darkAqua)
            case "light":
                NSApp.appearance = NSAppearance(named: .aqua)
            default:
                NSApp.appearance = nil
            }
        }
    }
    #endif
}
