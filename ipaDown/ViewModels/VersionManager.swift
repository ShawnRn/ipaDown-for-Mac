//
//  VersionManager.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// 版本管理 ViewModel
@Observable
class VersionManager {
    /// 当前查询的 App
    var currentApp: AppSoftware?
    
    /// 版本列表
    var versions: [VersionInfo] = []
    
    /// 正在加载
    var isLoading = false
    
    /// 正在加载更多
    var isLoadingMore = false
    
    /// 是否还有更多数据
    var hasMore = false
    
    /// 正在加载详情的数量
    var loadingDetailCount = 0
    
    /// 当前页码
    var currentPage = 1
    
    /// Apple API 所有版本 ID (用于分页)
    private var allAppleVersionIds: [String] = []
    
    /// 错误信息
    var errorMessage: String?
    
    /// 选中的版本
    var selectedVersion: VersionInfo?
    
    /// 是否启用「免更新」功能 (持久化)
    var skipUpdate: Bool = (UserDefaults.standard.object(forKey: "skipUpdateByDefault") == nil ? true : UserDefaults.standard.bool(forKey: "skipUpdateByDefault")) {
        didSet {
            UserDefaults.standard.set(skipUpdate, forKey: "skipUpdateByDefault")
        }
    }
    
    private let logger = AppLogger.shared
    
    /// 版本数据源
    enum VersionSource: String, CaseIterable, Identifiable {
        case auto = "自动 (推荐)"
        case bilin = "第三方 API"
        case apple = "Apple API"
        
        var id: String { rawValue }
    }
    
    /// 当前选中的数据源
    var versionSource: VersionSource = .auto // 默认使用自动
    
    // MARK: - 版本操作
    
    /// 加载历史版本列表 (第一页)
    func loadVersions(account: Account, app: AppSoftware, accountManager: AccountManager) async {
        let isSameApp = (currentApp?.trackId == app.trackId)
        currentApp = app
        isLoading = true
        errorMessage = nil
        
        // 如果是同一个 App (例如切换源)，暂不清空列表，防止 UI 闪烁
        // 如果是不同 App，立即清空
        if !isSameApp {
            versions = []
        }
        
        currentPage = 1
        hasMore = true
        allAppleVersionIds = []
        
        switch versionSource {
        case .auto, .bilin:
            do {
                logger.info("VersionManager", "尝试使用 Bilin API 获取历史版本...")
                let (firstPageVersions, more) = try await VersionService.getVersionHistoryFromBilin(appId: app.trackId, page: 1)
                
                if !firstPageVersions.isEmpty {
                    self.versions = firstPageVersions
                    // 去重
                    let uniqueIds = Set(self.versions.map(\.externalVersionId))
                    if uniqueIds.count != self.versions.count {
                        var unique: [VersionInfo] = []
                        var seen: Set<String> = []
                        for v in self.versions {
                            if !seen.contains(v.externalVersionId) {
                                unique.append(v)
                                seen.insert(v.externalVersionId)
                            }
                        }
                        self.versions = unique
                    }
                    self.hasMore = more
                    self.isLoading = false
                    return
                }
                
                if versionSource == .bilin {
                    // 强制 Bilin 但为空
                    errorMessage = "第三方 API 返回为空，请尝试切换到 Apple API"
                    isLoading = false
                    return
                }
                
                // Auto 模式且为空，可能是没收录，降级
                logger.warning("VersionManager", "Bilin API 返回为空，自动降级到 Apple API...")
                
            } catch {
                if versionSource == .bilin {
                    logger.error("VersionManager", "Bilin API 失败: \(error.localizedDescription)")
                    errorMessage = "第三方 API 请求失败: \(error.localizedDescription)"
                    isLoading = false
                    return
                }
                logger.error("VersionManager", "Bilin API 失败，自动降级...")
            }
            
            fallthrough
            
        case .apple:
            await loadAppleVersions(account: account, app: app, accountManager: accountManager)
        }
    }
    
    // 辅助: 添加并去重
    private func appendVersions(_ newVersions: [VersionInfo]) {
        let existingIds = Set(self.versions.map(\.externalVersionId))
        let uniqueNew = newVersions.filter { !existingIds.contains($0.externalVersionId) }
        self.versions.append(contentsOf: uniqueNew)
    }
    
    /// 加载下一页
    func loadNextPage(account: Account) async {
        guard let app = currentApp, !isLoading, !isLoadingMore, hasMore else { return }
        
        isLoadingMore = true
        let nextPage = currentPage + 1
        
        switch versionSource {
        case .auto, .bilin:
            // 注意：如果是 Auto 模式且之前 fallback 到了 Apple，这里应该继续用 Apple。
            // 但简单的实现是：如果 versions 不为空且 allAppleVersionIds 为空，说明是 Bilin 数据。
            if !allAppleVersionIds.isEmpty {
                await loadNextApplePage(account: account, app: app)
                } else {
                do {
                    let (newVersions, more) = try await VersionService.getVersionHistoryFromBilin(appId: app.trackId, page: nextPage)
                    appendVersions(newVersions)
                    self.hasMore = more
                    self.currentPage = nextPage
                } catch {
                    logger.error("VersionManager", "加载下一页失败: \(error.localizedDescription)")
                    // 不中断，用户可以重试
                }
            }
            
        case .apple:
            await loadNextApplePage(account: account, app: app)
        }
        
        isLoadingMore = false
    }
    
    // MARK: - Apple API Logic
    
    // MARK: - Apple API Logic
    
    private func loadAppleVersions(account: Account, app: AppSoftware, accountManager: AccountManager, retryCount: Int = 0) async {
        do {
            let versionIds = try await VersionService.listVersionIds(
                account: account,
                appId: app.trackId
            )
            
            allAppleVersionIds = versionIds
            
            if versionIds.isEmpty {
                isLoading = false
                hasMore = false
                return
            }
            
            // 加载第一批详情 (比如前 20 个)
            await loadNextApplePage(account: account, app: app)
            isLoading = false
            
        } catch IPAError.tokenExpired {
            // Token 过期，尝试自动刷新
            if retryCount < 1 {
                logger.warning("VersionManager", "Token 已过期，尝试自动刷新...")
                if let refreshed = await accountManager.refreshToken(for: account) {
                    // 刷新成功，重试
                    logger.success("VersionManager", "Token 刷新成功，重试查询...")
                    await loadAppleVersions(account: refreshed, app: app, accountManager: accountManager, retryCount: retryCount + 1)
                    return
                } else {
                    errorMessage = "Token 已过期且自动刷新失败，请手动重新登录"
                    isLoading = false
                }
            } else {
                errorMessage = "Token 已过期，请重新登录"
                isLoading = false
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    private func loadNextApplePage(account: Account, app: AppSoftware) async {
        let pageSize = 20
        let currentCount = versions.count
        let total = allAppleVersionIds.count
        
        guard currentCount < total else {
            hasMore = false
            return
        }
        
        let end = min(currentCount + pageSize, total)
        let idsToLoad = Array(allAppleVersionIds[currentCount..<end])
        
        // 创建临时版本对象
        // 暂时先加进去显示 loading 状态? 或者等详情加载完？
        // 现有逻辑是先加 ID，再异步刷新详情。为了体验好，我们先加进去。
        // 但是 Apple API 的批量详情是批处理的，所以最好等详情回来再显示，或者显示骨架屏。
        // 这里为了简单，先不加到 versions，等详情回来。
        
        // 批量加载详情
        loadingDetailCount = idsToLoad.count
        
        var loadedItems: [VersionInfo] = []
        
        // 我们需要保留顺序，idsToLoad 的顺序。
        // batchGetVersionMetadata 是 async stream，顺序可能乱。
        // 先创建 dict
        var infoMap: [String: VersionInfo] = [:]
        for id in idsToLoad {
            infoMap[id] = VersionInfo(externalVersionId: id)
        }
        
        for await (versionId, info) in VersionService.batchGetVersionMetadata(
            account: account,
            appId: app.trackId,
            versionIds: idsToLoad
        ) {
            if let info = info, var item = infoMap[versionId] {
                item.displayVersion = info.displayVersion
                item.releaseDate = info.releaseDate
                infoMap[versionId] = item
            }
            loadingDetailCount -= 1
        }
        
        // 按原顺序重组
        for id in idsToLoad {
            if let item = infoMap[id] {
                loadedItems.append(item)
            }
        }
        

        
        appendVersions(loadedItems)
        self.currentPage += 1 // Apple 逻辑其实不需要页码，只要 count
        self.hasMore = self.versions.count < self.allAppleVersionIds.count
    }
    
    /// 清空版本列表
    func clear() {
        currentApp = nil
        versions = []
        selectedVersion = nil
        errorMessage = nil
        allAppleVersionIds = []
        currentPage = 1
        hasMore = false
    }
}
