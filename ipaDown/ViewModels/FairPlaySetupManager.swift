#if os(macOS)
import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class FairPlaySetupManager {
    var step = 0
    var apps: [FairPlayInstalledApp] = []
    var selectedApp: FairPlayInstalledApp?
    var ipaURL: URL?
    var referenceURL: URL?
    var selectedAccountEmail = ""
    var isBusy = false
    var isGenerating = false
    var message = ""
    var error: String?
    var downloadTask: IPADownloadTask?
    var accountConfirmed = false

    var canGenerateOnThisMac: Bool {
        #if arch(arm64)
        // 上游在带小写 seed 后缀的构建上拒绝恢复。
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        let build = version.split(separator: " ").last?.trimmingCharacters(in: CharacterSet(charactersIn: ")")) ?? ""
        return build.last?.isLowercase != true
        #else
        return false
        #endif
    }

    func scan() async {
        isBusy = true
        defer { isBusy = false }
        apps = await FairPlaySetupService.scanApplications()
        if selectedApp == nil { selectedApp = apps.first }
    }

    func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "选择从 Mac App Store 安装的 iPhone / iPad 应用"
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let app = try FairPlaySetupService.installedApp(at: url)
            if !apps.contains(app) { apps.append(app) }
            selectedApp = app
            ipaURL = nil
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func chooseIPA() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ipa") ?? .data]
        panel.title = "选择与已安装应用授权状态匹配的 IPA"
        guard panel.runModal() == .OK, let url = panel.url, let app = selectedApp else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await FairPlaySetupService.validateIPA(url, app: app)
            ipaURL = url
            error = nil
            message = "已验证应用和 IPA 的授权状态匹配。"
        } catch { self.error = error.localizedDescription }
    }

    func prepareIPA(downloads: DownloadManager, accounts: AccountManager) async {
        guard let app = selectedApp else { return }
        error = nil
        isBusy = true
        defer { isBusy = false }
        do {
            ipaURL = nil
            downloadTask = nil
            // 展示版本只用来排序；必须读取包内版本与构建号才能接受样本。
            for existing in downloads.tasks where existing.status == .completed && existing.bundleId == app.bundleID && existing.accountEmail == selectedAccountEmail {
                if let url = existing.filePath, (try? await FairPlaySetupService.validateIPA(url, app: app)) != nil {
                    ipaURL = url
                    message = "已验证已有 IPA 与 Mac 应用的FairPlay 授权状态匹配。"
                    return
                }
            }
            guard var account = accounts.accounts.first(where: { $0.email == selectedAccountEmail }) else {
                throw IPAError.decryptionFailed("请先登录 Mac App Store 所用的 Apple 账号。")
            }
            message = "正在查找 Mac 应用 \(app.version)（构建 \(app.build)）的真实下载版本…"
            let software = try await SearchService.lookupByBundleId(app.bundleID, countryCode: account.countryCode ?? "CN")
            try await authenticated(account: &account, accounts: accounts) { current in
                var updated = current
                try await PurchaseService.purchase(account: &updated, appId: software.trackId)
            }
            var candidates = [String]()
            var seen = Set<String>()
            func append(_ id: String) { if seen.insert(id).inserted { candidates.append(id) } }
            append("") // 先核对 Apple 当前实际提供的包，不相信商店展示版本。
            var matching = [String]()
            var unknown = [String]()
            var discoveryErrors = [String]()
            do {
                var more = true
                var page = 1
                while more && page <= 20 {
                    try Task.checkCancellation()
                    let (versions, hasMore) = try await VersionService.getVersionHistoryFromBilin(appId: software.trackId, page: page)
                    for version in versions {
                        if version.displayVersion == app.version { matching.append(version.externalVersionId) }
                        else if version.displayVersion == nil { unknown.append(version.externalVersionId) }
                    }
                    more = hasMore
                    page += 1
                }
            } catch { discoveryErrors.append(error.localizedDescription) }
            for id in matching { append(id) }
            // Apple 自己的历史版本列表作为另一条发现路径。
            do {
                let ids = try await authenticated(account: &account, accounts: accounts) { current in
                    try await VersionService.listVersionIds(account: current, appId: software.trackId)
                }
                for id in ids {
                    try Task.checkCancellation()
                    if seen.contains(id) { continue }
                    let metadata = try await VersionService.getVersionMetadata(account: account, appId: software.trackId, versionId: id)
                    if metadata.displayVersion == app.version || metadata.displayVersion == nil { append(id) }
                }
            } catch {
                if case IPAError.tokenExpired = error { throw error }
                if case IPAError.codeRequired = error { throw error }
                discoveryErrors.append(error.localizedDescription)
            }
            for id in unknown { append(id) }
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = support.appendingPathComponent("ipaDown/UnfairPlay/samples", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var lastFailure = "未找到可用下载项"
            for (index, id) in candidates.enumerated() {
                try Task.checkCancellation()
                message = "正在核对候选 \(index + 1)/\(candidates.count)：目标 \(app.version)（构建 \(app.build)）…"
                let file = directory.appendingPathComponent(UUID().uuidString + ".ipa")
                do {
                    let info = try await authenticated(account: &account, accounts: accounts) { current in
                        try await DownloadService.requestDownload(account: current, appId: software.trackId, versionId: id)
                    }
                    try await DownloadService.downloadFile(from: info.downloadURL, to: file) { _, _, _, _, _ in }
                    try await SignatureService.signIPA(at: file, sinfs: info.sinfs, metadata: info.metadata)
                    try await FairPlaySetupService.validateIPA(file, app: app)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                    ipaURL = file
                    message = "已找到并下载匹配 IPA：\(app.version)（构建 \(app.build)），包内核对通过。"
                    return
                } catch {
                    try? FileManager.default.removeItem(at: file)
                    if error is CancellationError { throw error }
                    if case IPAError.tokenExpired = error { throw error }
                    lastFailure = error.localizedDescription
                }
            }
            throw IPAError.decryptionFailed("已自动核对 \(candidates.count) 个候选，尚未找到匹配样本，不能据此判定 Apple 不提供该版本。目标：\(app.bundleID) \(app.version)（构建 \(app.build)）。\n最后结果：\(lastFailure)\n\(discoveryErrors.joined(separator: "\n"))")
        } catch {
            message = "自动准备未完成，尚未验证样本。"
            self.error = error.localizedDescription
        }
    }

    private func authenticated<T>(account: inout Account, accounts: AccountManager, operation: (Account) async throws -> T) async throws -> T {
        do { return try await operation(account) }
        catch IPAError.tokenExpired {
            message = "正在更新 Apple 会话并重试原请求…"
            let refreshed = try await AuthService.refreshToken(for: account)
            accounts.updateAccount(refreshed)
            account = refreshed
            return try await operation(refreshed)
        }
    }

    func chooseReference() {
        let panel = NSOpenPanel()
        panel.title = "选择 UnfairPlay 要求的精确 fairplayd arm64e 参考文件"
        guard panel.runModal() == .OK else { return }
        referenceURL = panel.url
        error = nil
    }

    func generate(using manager: DecryptionManager) async {
        guard !isBusy, !manager.isRunning, !manager.isSettingUp,
              let app = selectedApp, let ipa = ipaURL, let engine = manager.engineURL else { return }
        isBusy = true
        isGenerating = true
        manager.isSettingUp = true
        error = nil
        message = "请在系统窗口中授权。随后将自动提取授权状态、生成模型，并用匹配 IPA 验证。此过程可能需要几分钟。"
        defer { isBusy = false; isGenerating = false; manager.isSettingUp = false }
        do {
            try await FairPlaySetupService.generateModel(engine: engine, app: app.url, ipa: ipa, models: manager.prepareModelDirectory(), reference: referenceURL, user: NSUserName(), uid: getuid(), gid: getgid())
            manager.refreshModels()
            guard manager.modelCount > 0 else { throw IPAError.decryptionFailed("初始化结束但未找到模型，请重试。") }
            message = "私有模型已生成并通过匹配 IPA 验证。"
            step = 4
        } catch { self.error = error.localizedDescription }
    }

    func openAppStore() {
        if let url = URL(string: "macappstore://") { NSWorkspace.shared.open(url) }
    }

    func openSelectedApp() {
        if let selectedApp { NSWorkspace.shared.open(selectedApp.url) }
    }
}
#endif
