//
//  SettingsView.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            GeneralSettingsTab(isSectionOnly: true)
            DownloadsSettingsTab(isSectionOnly: true)
            NetworkSettingsTab(isSectionOnly: true)
        }
        #if os(macOS)
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 550)
        #endif
        .navigationTitle("设置")
    }
}

// MARK: - Tab Views (Keeping same as before)

struct GeneralSettingsTab: View {
    var isSectionOnly: Bool = false
    @AppStorage("theme") private var theme = "auto"
    @AppStorage("autoJumpOnTaskCreated") private var autoJumpOnTaskCreated = true
    
    var body: some View {
        if isSectionOnly {
            content
        } else {
            Form {
                content
            }
            .formStyle(.grouped)
        }
    }
    
    @ViewBuilder
    private var content: some View {
        Section("通用") {
            Picker("外观", selection: $theme) {
                Text("跟随系统").tag("auto")
                Text("浅色").tag("light")
                Text("深色").tag("dark")
            }
            
            Toggle("新建任务后跳转下载页", isOn: $autoJumpOnTaskCreated)
                .help("创建下载任务后自动切换到下载管理页面")
        }
        
        Section("语言与地区") {
            Picker("语言", selection: .constant("zh-Hans")) {
                Text("简体中文").tag("zh-Hans")
            }
            .disabled(true)
        }
        
        #if os(macOS)
        Section("日志与诊断") {
            @Bindable var logger = AppLogger.shared
            Picker("日志级别", selection: $logger.minLevel) {
                ForEach(AppLogger.LogEntry.Level.allCases.filter { $0 != .success }, id: \.self) { level in
                    Text(level.name).tag(level)
                }
            }
            
            Button("清空操作日志", role: .destructive) {
                AppLogger.shared.clear()
            }
            .buttonStyle(.bordered)
        }
        #endif
    }
}

struct DownloadsSettingsTab: View {
    var isSectionOnly: Bool = false
    @Environment(DownloadManager.self) private var downloadManager
    @AppStorage("maxConcurrentDownloads") private var maxConcurrent = 3
    @AppStorage("autoRenameFiles") private var autoRename = true
    
    var body: some View {
        if isSectionOnly {
            content
        } else {
            Form {
                content
            }
            .formStyle(.grouped)
        }
    }
    
    @ViewBuilder
    private var content: some View {
        Section("下载") {
            #if os(macOS)
            HStack {
                Text("下载位置")
                Spacer()
                Text(shortenPath(downloadManager.downloadDirectory.path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Button {
                    downloadManager.selectDownloadDirectory()
                } label: {
                    Image(systemName: "folder")
                }
            }
            #endif
            
            Toggle("自动重命名已存在文件", isOn: $autoRename)
        }
        
        Section("并发设置") {
            Stepper("最大同时下载数：\(maxConcurrent)", value: $maxConcurrent, in: 1...10)
        }
    }
    
    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return path.replacingOccurrences(of: home, with: "~")
        }
        return path
    }
}

struct NetworkSettingsTab: View {
    var isSectionOnly: Bool = false
    @AppStorage("proxyEnabled") private var proxyEnabled = false
    @AppStorage("proxyHost") private var proxyHost = "127.0.0.1"
    @AppStorage("proxyPort") private var proxyPort = "7890"
    @AppStorage("customUserAgent") var customUA = "ipaDown"
    
    var body: some View {
        if isSectionOnly {
            content
        } else {
            Form {
                content
            }
            .formStyle(.grouped)
        }
    }
    
    @ViewBuilder
    private var content: some View {
        Section("网络代理") {
            Toggle("启用代理", isOn: $proxyEnabled)
            
            if proxyEnabled {
                TextField("主机 IP", text: $proxyHost)
                TextField("端口", text: $proxyPort)
            }
        }
        
        Section("请求设置") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("User-Agent")
                    Spacer()
                    Button("恢复默认") {
                        customUA = "ipaDown"
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                TextField("请输入自定义 User-Agent", text: $customUA, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(DownloadManager())
}
