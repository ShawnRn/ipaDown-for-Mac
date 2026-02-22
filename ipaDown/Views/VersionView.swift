//
//  VersionView.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import SwiftUI

/// 历史版本视图
struct VersionView: View {
    @Environment(VersionManager.self) private var versionManager
    @Environment(AccountManager.self) private var accountManager
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(SearchManager.self) private var searchManager
    @Environment(NavigationManager.self) private var nav
    
    @State private var manualAppId = ""
    @State private var sortOrder = [KeyPathComparator(\VersionInfo.releaseDate, order: .reverse)]
    
    // MARK: - Computed Properties
    
    private var sortedVersions: [VersionInfo] {
        let sorted = versionManager.versions.sorted(using: sortOrder)
        // 二次去重，确保 View 不会 crash
        var unique: [VersionInfo] = []
        var seen: Set<String> = []
        for v in sorted {
            if !seen.contains(v.externalVersionId) {
                unique.append(v)
                seen.insert(v.externalVersionId)
            }
        }
        return unique
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部信息
                headerSection
                    .padding()
                
                Divider()
                
                // 版本列表
                ZStack {
                    if !versionManager.versions.isEmpty {
                        versionsList
                            .opacity(versionManager.isLoading ? 0.6 : 1.0) // Loading 时稍微变淡
                            .disabled(versionManager.isLoading) // 禁止交互
                    }
                    
                    if versionManager.isLoading {
                        ProgressView()
                            .controlSize(.large)
                            //.background(.regularMaterial) // 用户要求去除背景
                            //.cornerRadius(12)
                    } else if let error = versionManager.errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 36))
                                .foregroundStyle(.orange)
                            
                            Text(error)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            if error.contains("许可") || error.contains("license") || error.contains("License") {
                                Text("此应用尚未在当前账号下获取过许可\n请先点击下方按钮获取免费许可，然后自动查询版本")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                
                                Button {
                                    Task { await acquireLicenseAndReload() }
                                } label: {
                                    Label("获取许可并查询版本", systemImage: "arrow.down.circle")
                                }
                                .disabled(accountManager.activeAccount == nil || versionManager.isLoading)
                            } else {
                                // 提供重试按钮
                                Button("重试") {
                                    Task {
                                        if let app = versionManager.currentApp,
                                           let account = accountManager.activeAccount {
                                            await versionManager.loadVersions(account: account, app: app, accountManager: accountManager)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(versionManager.versions.isEmpty ? AnyShapeStyle(Color.clear) : AnyShapeStyle(.regularMaterial))
                    } else if versionManager.versions.isEmpty {
                        // 空状态
                        if versionManager.currentApp != nil {
                            ContentUnavailableView(
                                "历史版本",
                                systemImage: "slash.circle",
                                description: Text("未找到该应用的历史版本信息")
                            )
                        } else {
                            ContentUnavailableView(
                                "查询历史版本",
                                systemImage: "magnifyingglass",
                                description: Text("请先在搜索页面选择一个 App，或上方输入 App ID")
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("历史版本")
        }
    }
    
    // MARK: - 顶部信息
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            if let app = versionManager.currentApp {
                // App 信息行
                HStack(spacing: 12) {
                    AsyncImage(url: app.bestIconURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.quaternary)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    VStack(alignment: .leading) {
                        Text(app.trackName)
                            .font(.headline)
                            .lineLimit(1)
                        Text("ID: \(app.trackId) · v\(app.version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Text("\(versionManager.versions.count) 个版本")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                }
                
                // 控制行：数据源 + 免更新 + 加载中
                HStack(spacing: 12) {
                    // 数据源选择
                    Menu {
                        Picker("数据源", selection: Bindable(versionManager).versionSource) {
                            ForEach(VersionManager.VersionSource.allCases) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                    } label: {
                        Label(versionManager.versionSource.rawValue, systemImage: "server.rack")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    #if os(macOS)
                    .menuStyle(.borderlessButton)
                    #endif
                    .foregroundStyle(.primary)
                    .onChange(of: versionManager.versionSource) { _, _ in
                        Task {
                            if let account = accountManager.activeAccount {
                                await versionManager.loadVersions(account: account, app: app, accountManager: accountManager)
                            }
                        }
                    }
                    
                    // 免更新开关（紧凑布局）
                    Toggle("免更新", isOn: Bindable(versionManager).skipUpdate)
                        #if os(macOS)
                        .toggleStyle(.checkbox)
                        #endif
                        .font(.caption)
                        .fixedSize()
                    
                    if versionManager.loadingDetailCount > 0 {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            Text("\(versionManager.loadingDetailCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                }
            } else {
                // 手动输入 App ID
                HStack(spacing: 10) {
                    TextField("输入 App ID", text: $manualAppId)
                        .textFieldStyle(.roundedBorder)
                        #if os(macOS)
                        .frame(width: 200)
                        #endif
                    
                    Button("查询版本") {
                        Task { await loadVersionsForManualId() }
                    }
                    .controlSize(.small)
                    
                    if accountManager.activeAccount == nil {
                        Text("⚠️ 请先登录账号")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }
    
    // MARK: - 版本列表
    
    @ViewBuilder
    private var versionsList: some View {
        versionsListContent
            .overlay(alignment: .bottom) {
                if versionManager.isLoadingMore {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("加载更多...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.regularMaterial)
                    .cornerRadius(8)
                    .padding(.bottom, 16)
                }
            }
    }
    
    @ViewBuilder
    private var versionsListContent: some View {
        #if os(macOS)
        Table(sortedVersions, sortOrder: $sortOrder) {
            TableColumn("版本号", value: \.displayVersionComparable) { version in
                HStack {
                    if let v = version.displayVersion {
                        Text(v)
                            .font(.body)
                            .fontWeight(.regular)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
                .frame(minHeight: 24)
                .onAppear {
                    if version == versionManager.versions.last {
                        Task {
                            if let account = accountManager.activeAccount {
                                await versionManager.loadNextPage(account: account)
                            }
                        }
                    }
                }
            }
            .width(min: 140, ideal: 180)
            
            TableColumn("发布日期", value: \.releaseDateComparable) { version in
                Text(version.formattedDate)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)
            
            TableColumn("版本 ID", value: \.id) { version in
                Text(version.externalVersionId)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)
            
            TableColumn("操作") { version in
                HStack(spacing: 8) {
                    Button("下载") {
                        downloadVersion(version)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(accountManager.activeAccount == nil)
                }
            }
            .width(min: 80, ideal: 100)
        }
        .tableStyle(.inset)
        #else
        List(sortedVersions) { version in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let v = version.displayVersion {
                            Text("v\(v)")
                                .font(.headline)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text(version.formattedDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("ID: \(version.externalVersionId)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
                
                Button("下载") {
                    downloadVersion(version)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(accountManager.activeAccount == nil)
            }
            .padding(.vertical, 2)
            .onAppear {
                if version == versionManager.versions.last {
                    Task {
                        if let account = accountManager.activeAccount {
                            await versionManager.loadNextPage(account: account)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        #endif
    }
    
    
    // MARK: - Actions
    
    private func loadVersionsForManualId() async {
        guard let appId = Int64(manualAppId),
              let account = accountManager.activeAccount else { return }
        
        // 先查找 App 信息
        do {
            let app = try await SearchService.lookup(appId: appId)
            await versionManager.loadVersions(account: account, app: app, accountManager: accountManager)
        } catch {
            versionManager.errorMessage = error.localizedDescription
        }
    }
    
    private func downloadVersion(_ version: VersionInfo) {
        guard let account = accountManager.activeAccount,
              let app = versionManager.currentApp else { return }
        
        downloadManager.addTask(
            app: app,
            versionId: version.externalVersionId,
            displayVersion: version.displayVersion ?? version.externalVersionId,
            account: account,
            skipUpdate: versionManager.skipUpdate
        )
        nav.navigate(to: .downloads)
    }
    
    private func acquireLicenseAndReload() async {
        guard var account = accountManager.activeAccount,
              let app = versionManager.currentApp else { return }
        
        versionManager.errorMessage = nil
        versionManager.isLoading = true
        
        do {
            try await PurchaseService.purchase(account: &account, appId: app.trackId, versionId: "0")
            // 更新账号（purchase 可能会更新 cookies）
            accountManager.updateAccount(account)
            // 重新查询版本
            await versionManager.loadVersions(account: account, app: app, accountManager: accountManager)
        } catch {
            versionManager.errorMessage = error.localizedDescription
            versionManager.isLoading = false
        }
    }
}
