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
            
            // 检查是否已存在该账号
            accounts.removeAll { $0.email == account.email }
            accounts.append(account)
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
        activeAccount = account
        logger.info("账号", "切换到账号: \(account.email)")
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
    
    private func saveAccounts() {
        try? KeychainHelper.saveCodable(accounts, forKey: "accounts")
    }
    
    private func loadAccounts() {
        if let saved = KeychainHelper.loadCodable([Account].self, forKey: "accounts") {
            accounts = saved
            activeAccount = accounts.first
        }
    }
    
    private func clearLoginForm() {
        loginEmail = ""
        loginPassword = ""
        twoFactorCode = ""
        needsTwoFactorCode = false
    }
}
