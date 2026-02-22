//
//  AccountManager.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// 账号管理 ViewModel
@Observable
class AccountManager {
    /// 已保存的账号列表
    var accounts: [Account] = []
    
    /// 当前活跃账号
    var activeAccount: Account?
    
    /// 登录状态
    var isLoggingIn = false
    
    /// 需要两步验证
    var needsTwoFactorCode = false
    
    /// 错误信息
    var errorMessage: String?
    
    /// 登录表单
    var loginEmail = ""
    var loginPassword = ""
    var twoFactorCode = ""
    
    private let logger = AppLogger.shared
    
    init() {
        loadAccounts()
    }
    
    // MARK: - 账号操作
    
    /// 登录
    func login() async {
        guard !loginEmail.isEmpty, !loginPassword.isEmpty else {
            errorMessage = "请输入邮箱和密码"
            return
        }
        
        isLoggingIn = true
        errorMessage = nil
        
        do {
            let account = try await AuthService.authenticate(
                email: loginEmail,
                password: loginPassword,
                code: twoFactorCode
            )
            
            // 检查是否已存在该账号，并将其置顶
            accounts.removeAll { $0.email == account.email }
            accounts.insert(account, at: 0)
            activeAccount = account
            
            saveAccounts()
            clearLoginForm()
            
        } catch IPAError.codeRequired {
            needsTwoFactorCode = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoggingIn = false
    }
    
    /// 提交两步验证码
    func submitTwoFactorCode() async {
        guard !twoFactorCode.isEmpty else {
            errorMessage = "请输入验证码"
            return
        }
        needsTwoFactorCode = false
        await login()
    }
    
    /// 删除账号
    func deleteAccount(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        if activeAccount?.id == account.id {
            activeAccount = accounts.first
        }
        saveAccounts()
        logger.info("账号", "已删除账号: \(account.email)")
    }
    
    /// 已登录账号的所有国家代码（去重排序）
    var availableCountryCodes: [String] {
        let codes = accounts.compactMap { $0.countryCode }
        return Array(Set(codes)).sorted()
    }
    
    /// 切换活跃账号
    func switchAccount(to account: Account) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            let selected = accounts.remove(at: index)
            accounts.insert(selected, at: 0)
            activeAccount = selected
            saveAccounts()
            logger.info("账号", "切换到账号并置顶: \(account.email)")
        }
    }
    
    /// 根据国家代码切换账号
    func switchToAccount(forCountryCode code: String) {
        if let account = accounts.first(where: { $0.countryCode == code }) {
            if activeAccount?.id != account.id {
                switchAccount(to: account)
            }
        }
    }
    
    /// 刷新 Token
    /// - Returns: 刷新后的 Account，失败则返回 nil
    @discardableResult
    func refreshToken(for account: Account) async -> Account? {
        do {
            let refreshed = try await AuthService.refreshToken(for: account)
            updateAccount(refreshed)
            logger.success("账号", "Token 刷新成功: \(account.email)")
            return refreshed
        } catch {
            logger.error("账号", "刷新 Token 失败 (\(account.email)): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 自动刷新所有账号的 Token
    func refreshAllTokens() async {
        logger.info("账号", "开始自动刷新所有账号 Token...")
        for account in accounts {
            await refreshToken(for: account)
        }
        logger.info("账号", "所有账号 Token 刷新尝试完成")
    }
    
    // MARK: - 持久化
    
    /// 更新已有账号数据（如 cookies 变更后）
    func updateAccount(_ account: Account) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        }
        if activeAccount?.id == account.id {
            activeAccount = account
        }
        saveAccounts()
    }
    
    private var accountsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ipaDown", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("accounts.json")
    }

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            try? data.write(to: accountsFileURL, options: .atomic)
        }
    }
    
    private func loadAccounts() {
        // 优先从严格专属沙盒目录读取 (.json 文件)
        if let data = try? Data(contentsOf: accountsFileURL),
           let saved = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = saved
            activeAccount = accounts.first
            
            // 例行清理，防止任何早期版本的残留滞留在 Keychain 或 UserDefaults 中
            KeychainHelper.delete(forKey: "accounts")
            UserDefaults.standard.removeObject(forKey: "accounts")
            return
        }
        
        // 向下兼容并迁移：如果在上一版本迁移中留在了 UserDefaults 里
        if let data = UserDefaults.standard.data(forKey: "accounts"),
           let saved = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = saved
            activeAccount = accounts.first
            saveAccounts()
            UserDefaults.standard.removeObject(forKey: "accounts")
            KeychainHelper.delete(forKey: "accounts")
            logger.info("账号", "成功从 UserDefaults 迁移账号数据至私有数据目录文件中，旧有痕迹已抹除")
            return
        }
        
        // 向下兼容并迁移：如果还有最老版本的残渣留在 Keychain 里
        if let saved = KeychainHelper.loadCodable([Account].self, forKey: "accounts") {
            accounts = saved
            activeAccount = accounts.first
            saveAccounts()
            KeychainHelper.delete(forKey: "accounts")
            logger.info("账号", "成功从旧版 Keychain 迁移账号数据至私有数据目录文件内，原缓存已抹除")
        }
    }
    
    private func clearLoginForm() {
        loginEmail = ""
        loginPassword = ""
        twoFactorCode = ""
        needsTwoFactorCode = false
    }
}
