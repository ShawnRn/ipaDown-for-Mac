//
//  SettingsView.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import SwiftUI

enum SettingsTab: String, Identifiable, CaseIterable {
    case general, downloads, network
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
        case .general: return "通用"
        case .downloads: return "下载"
        case .network: return "网络"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Sliding Tabs
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    
                    // Motrix-style Segmented Control
                    HStack(spacing: 0) {
                        ForEach(SettingsTab.allCases) { tab in
                            TabButton(
                                title: tab.title,
                                isSelected: selectedTab == tab
                            ) {
                                selectedTab = tab
                            }
                        }
                    }
                    .padding(4)
                    .background {
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor))
                    }
                    .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                    
                    Spacer()
                }
                .padding(.vertical, 16)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            ZStack {
                switch selectedTab {
                case .general:
                    GeneralSettingsTab()
                case .downloads:
                    DownloadsSettingsTab()
                case .network:
                    NetworkSettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 450)
    }
    
    private var tabTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

// MARK: - Components

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.accentColor)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab Views (Keeping same as before)

struct GeneralSettingsTab: View {
    @AppStorage("theme") private var theme = "auto"
    @AppStorage("autoJumpOnTaskCreated") private var autoJumpOnTaskCreated = true
    
    var body: some View {
        Form {
            Section("表现") {
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
        }
        .formStyle(.grouped)
    }
}

struct DownloadsSettingsTab: View {
    @Environment(DownloadManager.self) private var downloadManager
    @AppStorage("maxConcurrentDownloads") private var maxConcurrent = 3
    @AppStorage("autoRenameFiles") private var autoRename = true
    
    var body: some View {
        Form {
            Section("文件管理") {
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
                
                Toggle("自动重命名已存在文件", isOn: $autoRename)
            }
            
            Section("并发设置") {
                Stepper("最大同时下载数：\(maxConcurrent)", value: $maxConcurrent, in: 1...10)
            }
        }
        .formStyle(.grouped)
    }
    
    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return path.replacingOccurrences(of: home, with: "~")
        }
        return path
    }
}

struct NetworkSettingsTab: View {
    @AppStorage("proxyEnabled") private var proxyEnabled = false
    @AppStorage("proxyHost") private var proxyHost = "127.0.0.1"
    @AppStorage("proxyPort") private var proxyPort = "7890"
    @AppStorage("customUserAgent") var customUA = "ipaDown"
    
    var body: some View {
        Form {
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
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
        .environment(DownloadManager())
}
