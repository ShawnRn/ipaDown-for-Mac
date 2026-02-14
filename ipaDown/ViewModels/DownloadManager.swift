//
//  DownloadManager.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation
import SwiftUI

/// 下载管理 ViewModel
@Observable
class DownloadManager {
    /// 下载队列
    var tasks: [IPADownloadTask] = []
    
    /// 下载进度缓存 (用于重试或恢复)
    private var downloadTasks: [UUID: Task<Void, Never>] = [:]
    private var accountCache: [UUID: Account] = [:]
    
    /// 账号管理引用 (用于自动刷新 Token)
    var accountManager: AccountManager?
    
    /// 下载保存目录
    var downloadDirectory: URL {
        didSet {
            UserDefaults.standard.set(downloadDirectory.path, forKey: "DownloadDirectory")
        }
    }
    
    private let logger = AppLogger.shared
    
    private var saveTask: Task<Void, Never>?
    
    private var tasksFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ipaDown", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("tasks.json")
    }
    
    init() {
        if let path = UserDefaults.standard.string(forKey: "DownloadDirectory") {
            self.downloadDirectory = URL(fileURLWithPath: path)
        } else {
            self.downloadDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                .appendingPathComponent("ipaDown", isDirectory: true)
        }
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        
        // 加载持久化的任务
        loadTasks()
    }
    
    private func loadTasks() {
        guard FileManager.default.fileExists(atPath: tasksFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: tasksFileURL)
            let decodedTasks = try JSONDecoder().decode([IPADownloadTask].self, from: data)
            self.tasks = decodedTasks
            logger.info("下载", "已从磁盘恢复 \(tasks.count) 个任务")
        } catch {
            logger.error("下载", "加载持久化任务失败: \(error.localizedDescription)")
        }
    }
    
    func saveTasks() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
            
            do {
                let data = try JSONEncoder().encode(tasks)
                try data.write(to: tasksFileURL)
            } catch {
                logger.error("下载", "保存任务列表失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 下载操作
    
    /// 添加下载任务
    @discardableResult
    func addTask(
        app: AppSoftware,
        versionId: String = "",
        displayVersion: String = "",
        account: Account,
        skipUpdate: Bool = false
    ) -> IPADownloadTask {
        let task = IPADownloadTask(
            appName: app.trackName,
            appId: app.trackId,
            bundleId: app.bundleId,
            versionId: versionId,
            displayVersion: displayVersion.isEmpty ? app.version : displayVersion,
            accountEmail: account.email,
            skipUpdate: skipUpdate,
            iconURL: app.bestIconURL
        )
        
        tasks.insert(task, at: 0)
        accountCache[task.id] = account
        logger.info("下载", "添加任务: \(app.trackName) v\(task.displayVersion)")
        
        // 自动开始下载
        resumeTask(task)
        saveTasks()
        
        return task
    }
    
    /// 暂停/恢复任务
    func togglePause(task: IPADownloadTask) {
        if task.status == .paused || task.status == .failed {
            resumeTask(task)
        } else if task.status.isActive || task.status == .waiting {
            pauseTask(task)
        }
    }
    
    func pauseTask(_ task: IPADownloadTask) {
        downloadTasks[task.id]?.cancel()
        downloadTasks.removeValue(forKey: task.id)
        task.status = .paused
        task.speed = "已暂停"
        logger.info("下载", "暂停任务: \(task.appName)")
    }
    
    func resumeTask(_ task: IPADownloadTask) {
        // 优先从 AccountManager 获取最新的账号数据，确保 Token 刷新后任务能感知
        var account: Account?
        if let am = accountManager {
            account = am.accounts.first(where: { $0.email == task.accountEmail })
        }
        
        // 如果没找到（例如 AccountManager 未初始化或账号已删），尝试使用缓存
        if account == nil {
            account = accountCache[task.id]
        }
        
        guard let finalAccount = account else {
            logger.error("下载", "恢复任务失败: 找不到账号信息 (\(task.accountEmail))")
            return
        }
        
        let downloadTask = Task {
            await startDownload(task: task, account: finalAccount)
        }
        downloadTasks[task.id] = downloadTask
        logger.info("下载", "开始/恢复任务: \(task.appName)")
    }
    
    /// 开始下载
    func startDownload(task: IPADownloadTask, account: Account) async {
        var mutableAccount = account
        var retryCount = 0
        
        while retryCount < 2 {
            do {
                // 1. 尝试自动购买（获取许可）
                task.status = .purchasing
                
                do {
                    try await PurchaseService.purchase(account: &mutableAccount, appId: task.appId, versionId: task.versionId)
                } catch IPAError.purchaseFailed(_) {
                    // 已购买的应用会报错，忽略
                    logger.info("下载", "许可检查完成")
                }
                
                // 2. 获取下载信息
                task.status = .fetchingInfo
                let info = try await DownloadService.requestDownload(
                    account: mutableAccount,
                    appId: task.appId,
                    versionId: task.versionId
                )
                
                task.downloadURL = info.downloadURL
                task.sinfs = info.sinfs
                task.md5 = info.md5
                
                var finalInfo = info
                if task.skipUpdate {
                    // 免更新逻辑：注入极大版本 ID 及账号元数据
                    logger.info("下载", "正在为 \(task.appName) 注入免更新元数据 (极大 ID 方案)...")
                    var meta = info.metadata ?? [:]
                    let fakeVersionId: Int64 = 999888777
                    meta["softwareVersionExternalIdentifier"] = fakeVersionId
                    meta["softwareVersionExternalIdentifiers"] = [fakeVersionId]
                    
                    // 注入账号信息，确保显示为正版授权
                    meta["apple-id"] = mutableAccount.email
                    meta["userName"] = mutableAccount.email
                    meta["appleId"] = mutableAccount.email
                    // 额外注入 accountInfo 结构（适配某些场景）
                    meta["com.apple.iTunesStore.downloadInfo"] = ["accountInfo": ["AppleID": mutableAccount.email]]
                    
                    finalInfo.metadata = meta
                    logger.success("下载", "免更新元数据注入完成")
                }
                
                // 成功获取信息，跳出重试循环进入下载阶段
                try await performDownloadAndPostProcess(task: task, info: finalInfo)
                return
                
            } catch IPAError.tokenExpired {
                retryCount += 1
                if retryCount < 2, let am = accountManager {
                    logger.warning("下载", "Token 已过期，正在尝试自动刷新 (\(mutableAccount.email))...")
                    if let refreshed = await am.refreshToken(for: mutableAccount) {
                        mutableAccount = refreshed
                        continue // 刷新成功，重试
                    }
                }
                // 刷新失败或超过重试次数
                task.status = .failed
                task.error = "密码 Token 已过期，自动刷新失败，请在账号管理页重新登录。"
                logger.error("下载", "自动刷新 Token 失败")
                return
            } catch {
                task.status = .failed
                let errorMsg = error.localizedDescription
                task.error = errorMsg
                logger.error("下载", "下载失败: \(errorMsg)")
                
                // 如果是手动刷新后依然失败且没有进入 TokenExpired 逻辑
                // 可能是由于 StoreFront 之前丢失了导致服务器仍然报错。
                // 现在的 AuthService 已经通过保留 StoreFront 修复了此点。
                return
            }
        }
    }
    
    private func performDownloadAndPostProcess(task: IPADownloadTask, info: DownloadInfo) async throws {
        // 3. 下载文件
        task.status = .downloading
        let filePath = downloadDirectory.appendingPathComponent(task.fileName)
        
        try await DownloadService.downloadFile(
            from: info.downloadURL,
            to: filePath
        ) { progress, speedStr, rawSpeed, received, total in
            Task { @MainActor in
                task.progress = progress
                task.speed = speedStr
                task.receivedBytes = received
                task.totalBytes = total
                
                // Update history
                task.speedHistory.append(rawSpeed)
                if task.speedHistory.count > 60 {
                    task.speedHistory.removeFirst()
                }
            }
        }
        
        task.filePath = filePath
        
        // 后续处理（MD5校验、签名）在后台执行
        try await Task.detached(priority: .userInitiated) {
            // 4. MD5 校验（如果有预期值）
            if let expectedMD5 = info.md5, !expectedMD5.isEmpty {
                await MainActor.run { task.status = .verifying }
                // MD5Helper 可能是耗时操作
                let actualMD5 = try await MD5Helper.calculateMD5(of: filePath)
                if actualMD5.lowercased() != expectedMD5.lowercased() {
                    await MainActor.run {
                        self.logger.warning("下载", "MD5 不匹配，但继续签名: 预期 \(expectedMD5), 实际 \(actualMD5)")
                    }
                } else {
                    await MainActor.run {
                        self.logger.success("下载", "MD5 校验通过")
                    }
                }
            }
            
            // 5. 签名注入
            if !info.sinfs.isEmpty {
                await MainActor.run { task.status = .signing }
                // 签名操作包含解压/压缩，必须后台执行
                try await SignatureService.signIPA(
                    at: filePath,
                    sinfs: info.sinfs,
                    metadata: info.metadata
                    )
                }
            }.value
            
            // 完成
            if Task.isCancelled {
                logger.warning("下载", "任务已取消，跳过后续处理: \(task.fileName)")
                return
            }
            task.status = .completed
            task.progress = 1.0
            saveTasks()
            logger.success("下载", "下载完成: \(task.fileName)")
            
            // 发送系统通知
            NotificationService.shared.sendDownloadCompleteNotification(for: task)
    }
    
    /// 删除任务
    func removeTask(_ task: IPADownloadTask) {
        // 1. 立即停止后台下载线程
        downloadTasks[task.id]?.cancel()
        downloadTasks.removeValue(forKey: task.id)
        
        // 2. 从列表移除
        tasks.removeAll { $0.id == task.id }
        accountCache.removeValue(forKey: task.id)
        
        // 3. 删除物理文件
        if let path = task.filePath {
            try? FileManager.default.removeItem(at: path)
        }
        
        saveTasks()
        logger.info("下载", "已取消并删除任务: \(task.appName)")
    }
    
    /// 在 Finder 中显示
    func showInFinder(_ task: IPADownloadTask) {
        if let path = task.filePath {
            NSWorkspace.shared.selectFile(path.path, inFileViewerRootedAtPath: "")
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: downloadDirectory.path)
        }
    }
    
    /// 打开下载目录
    func showDownloadFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: downloadDirectory.path)
    }
    
    /// 选择下载目录
    func selectDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择 IPA 文件保存目录"
        
        if panel.runModal() == .OK, let url = panel.url {
            downloadDirectory = url
        }
    }
    
    /// 清除已完成的任务
    func clearCompleted() {
        tasks.removeAll { $0.status == .completed }
    }
}
