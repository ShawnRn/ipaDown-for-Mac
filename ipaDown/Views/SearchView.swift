//
//  SearchView.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import SwiftUI

/// 搜索视图
struct SearchView: View {
    @Environment(SearchManager.self) private var searchManager
    @Environment(AccountManager.self) private var accountManager
    @Environment(VersionManager.self) private var versionManager
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(NavigationManager.self) private var nav
    
    var body: some View {
        @Bindable var manager = searchManager
        
        VStack(spacing: 0) {
            // 搜索栏和过滤条件
            searchHeader
                .padding()
            
            Divider()
            
            // 搜索结果
            if searchManager.isSearching {
                Spacer()
                ProgressView("正在搜索...")
                Spacer()
            } else if let error = searchManager.errorMessage {
                Spacer()
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Spacer()
            } else if searchManager.results.isEmpty {
                ContentUnavailableView(
                    "搜索 App",
                    systemImage: "magnifyingglass",
                    description: Text("输入 App 名称、App Store 链接或 ID 进行搜索")
                )
            } else {
                resultsList
            }
        }
        .navigationTitle("App 搜索")
        .onAppear { syncCountryWithAccount() }
        .onChange(of: accountManager.activeAccount?.storeFront) { _, _ in
            syncCountryWithAccount()
        }
    }
    
    private func syncCountryWithAccount() {
        if let code = accountManager.activeAccount?.countryCode {
            searchManager.countryCode = code
        }
    }
    
    // MARK: - 搜索头部
    
    private var searchHeader: some View {
        @Bindable var manager = searchManager
        
        return VStack(spacing: 12) {
            SearchBar(text: $manager.searchText) {
                Task { await searchManager.search() }
            }
            
            ViewThatFits(in: .horizontal) {
                // Wide layout (iPad landscape, macOS)
                HStack(spacing: 16) {
                    searchFiltersContent
                }
                
                // Narrow layout (iPhone portrait)
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        // 商店国家/地区选择
                        countryPicker
                        Spacer()
                        // 设备类型
                        deviceTypePicker
                    }
                    HStack {
                        resultLimitPicker
                        Spacer()
                        searchButton
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var searchFiltersContent: some View {
        // 商店国家/地区选择
        countryPicker
        
        // 设备类型
        deviceTypePicker
        
        // 数量
        resultLimitPicker
        
        Spacer()
        
        searchButton
    }
    
    private var countryPicker: some View {
        @Bindable var manager = searchManager
        return HStack(spacing: 6) {
            Text("商店:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $manager.countryCode) {
                if accountManager.availableCountryCodes.isEmpty {
                    Text("未登录").tag("CN")
                } else {
                    ForEach(accountManager.availableCountryCodes, id: \.self) { code in
                        Text("\(CountryCodes.countryName(for: code)) (\(code))").tag(code)
                    }
                }
            }
            #if os(macOS)
            .frame(width: 130)
            #endif
            .onChange(of: manager.countryCode) { _, newValue in
                accountManager.switchToAccount(forCountryCode: newValue)
            }
        }
        .fixedSize()
    }
    
    private var deviceTypePicker: some View {
        @Bindable var manager = searchManager
        return Picker("", selection: $manager.deviceType) {
            ForEach(DeviceType.allCases, id: \.self) { type in
                Text(type.displayName).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 150)
    }
    
    private var resultLimitPicker: some View {
        @Bindable var manager = searchManager
        return HStack(spacing: 6) {
            Text("数量:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $manager.resultLimit) {
                Text("5").tag(5)
                Text("10").tag(10)
                Text("20").tag(20)
                Text("50").tag(50)
            }
            .frame(width: 70)
        }
    }
    
    private var searchButton: some View {
        Button("搜索") {
            Task { await searchManager.search() }
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(searchManager.searchText.isEmpty || searchManager.isSearching)
    }
    
    // MARK: - 搜索结果列表
    
    private var resultsList: some View {
        List(searchManager.results) { app in
            AppRow(app: app) {
                // 查看历史版本
                searchManager.selectedApp = app
                if let account = accountManager.activeAccount {
                    Task {
                        await versionManager.loadVersions(account: account, app: app, accountManager: accountManager)
                    }
                    nav.navigate(to: .versions)
                }
            } onDownload: {
                // 直接下载最新版本
                if let account = accountManager.activeAccount {
                    downloadManager.addTask(app: app, account: account)
                    nav.navigate(to: .downloads)
                }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - App 行

struct AppRow: View {
    let app: AppSoftware
    var onViewVersions: () -> Void
    var onDownload: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // App 图标
            AsyncImage(url: app.bestIconURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "app")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // App 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(app.trackName)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(app.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 详情
            VStack(alignment: .trailing, spacing: 4) {
                Text("v\(app.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(app.formattedSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 4) {
                    Text("ID: \(app.trackId)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    if let price = app.formattedPrice {
                        Text(price)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(price == "免费" || price == "Free" ? .green.opacity(0.1) : .orange.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            
            // 操作按钮
            VStack(spacing: 6) {
                Button("历史") {
                    onViewVersions()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                
                Button("下载") {
                    onDownload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
