//
//  AccountView.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import SwiftUI

/// 账号管理视图
struct AccountView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var isRefreshing = false
    @State private var showingRefreshResult = false
    @State private var refreshResultTitle = ""
    @State private var refreshResultMessage = ""
    
    var body: some View {
        @Bindable var manager = accountManager
        
        ScrollView {
            VStack(spacing: 20) {
                // 当前账号信息
                if let account = accountManager.activeAccount {
                    activeAccountSection(account)
                }
                
                // 登录表单
                loginSection
                
                // 已有账号列表
                if !accountManager.accounts.isEmpty {
                    accountsListSection
                }
            }
            .padding()
        }
        .navigationTitle("账号管理")
        .sheet(isPresented: .init(
            get: { accountManager.needsTwoFactorCode },
            set: { if !$0 { accountManager.needsTwoFactorCode = false } }
        )) {
            twoFactorSheet
        }
        .alert(refreshResultTitle, isPresented: $showingRefreshResult) {
            Button("好", role: .cancel) { }
        } message: {
            Text(refreshResultMessage)
        }
    }
    
    // MARK: - 当前账号
    
    @ViewBuilder
    private func activeAccountSection(_ account: Account) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.displayName)
                            .font(.headline)
                        Text(account.email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        if let code = account.countryCode {
                            Text(CountryCodes.countryName(for: code))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        
                        Text("Store: \(account.storeFront)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                HStack {
                    Text("Apple ID: \(account.appleId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button {
                        Task {
                            isRefreshing = true
                            if let refreshed = await accountManager.refreshToken(for: account) {
                                refreshResultTitle = "刷新成功"
                                refreshResultMessage = "账号 \(refreshed.email) 的 Token 已成功更新。"
                            } else {
                                refreshResultTitle = "刷新失败"
                                refreshResultMessage = "请检查网络连接或尝试重新登录。"
                            }
                            isRefreshing = false
                            showingRefreshResult = true
                        }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("刷新 Token")
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(isRefreshing)
                }
            }
        }
    }
    
    // MARK: - 登录表单
    
    private var loginSection: some View {
        @Bindable var manager = accountManager
        
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("登录 Apple 账号", systemImage: "key")
                    .font(.headline)
                
                TextField("Apple ID (邮箱)", text: $manager.loginEmail)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .onSubmit { performLogin() }
                
                SecureField("密码", text: $manager.loginPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .onSubmit { performLogin() }
                
                if let error = accountManager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                
                HStack {
                    Spacer()
                    
                    Button {
                        performLogin()
                    } label: {
                        if accountManager.isLoggingIn {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("登录")
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(accountManager.isLoggingIn)
                }
            }
        }
    }
    
    private func performLogin() {
        guard !accountManager.isLoggingIn else { return }
        Task { await accountManager.login() }
    }
    
    // MARK: - 账号列表
    
    private var accountsListSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("已保存的账号", systemImage: "person.2")
                    .font(.headline)
                
                ForEach(accountManager.accounts) { account in
                    HStack {
                        Image(systemName: account.id == accountManager.activeAccount?.id
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(account.id == accountManager.activeAccount?.id
                                           ? .blue : .secondary)
                        
                        VStack(alignment: .leading) {
                            Text(account.email)
                                .font(.body)
                            if let code = account.countryCode {
                                Text(CountryCodes.countryName(for: code))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button {
                            accountManager.switchAccount(to: account)
                        } label: {
                            Text("切换")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .disabled(account.id == accountManager.activeAccount?.id)
                        
                        Button(role: .destructive) {
                            accountManager.deleteAccount(account)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                    .padding(.vertical, 4)
                    
                    if account.id != accountManager.accounts.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
    
    // MARK: - 两步验证
    
    private var twoFactorSheet: some View {
        @Bindable var manager = accountManager
        
        return VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 50))
                .foregroundStyle(.blue)
            
            Text("两步验证")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("请输入发送到你的设备上的验证码")
                .font(.body)
                .foregroundStyle(.secondary)
            
            // Apple 风格 6 位验证码输入
            OTPInputView(code: $manager.twoFactorCode, onComplete: {
                submitTwoFactor()
            })
            
            if let error = accountManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            HStack(spacing: 12) {
                Button("取消") {
                    accountManager.needsTwoFactorCode = false
                }
                
                Button("提交") {
                    submitTwoFactor()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(accountManager.twoFactorCode.count < 6 || accountManager.isLoggingIn)
            }
        }
        .padding(40)
        .frame(width: 400)
    }
    
    private func submitTwoFactor() {
        guard accountManager.twoFactorCode.count == 6, !accountManager.isLoggingIn else { return }
        Task { await accountManager.submitTwoFactorCode() }
    }
}

// MARK: - Apple 风格 6 位 OTP 输入

struct OTPInputView: View {
    @Binding var code: String
    var onComplete: () -> Void
    
    @FocusState private var focusedIndex: Int?
    @State private var digits: [String] = Array(repeating: "", count: 6)
    
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<6, id: \.self) { index in
                OTPDigitBox(
                    digit: $digits[index],
                    isFocused: focusedIndex == index
                )
                .focused($focusedIndex, equals: index)
                .onChange(of: digits[index]) { _, newValue in
                    handleInput(at: index, value: newValue)
                }
                .onKeyPress(.delete) {
                    handleDelete(at: index)
                    return .handled
                }
                
                // 在第 3 位和第 4 位之间加分隔
                if index == 2 {
                    Text("–")
                        .font(.title2)
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .onAppear {
            focusedIndex = 0
            syncFromCode()
        }
        .onChange(of: code) { _, _ in
            syncFromCode()
        }
    }
    
    private func handleInput(at index: Int, value: String) {
        // 处理粘贴多位数字
        if value.count > 1 {
            let filtered = String(value.filter { $0.isNumber }.prefix(6))
            fillDigits(from: filtered, startingAt: index)
            return
        }
        
        // 只允许数字
        let filtered = value.filter { $0.isNumber }
        if filtered != value {
            digits[index] = filtered
            return
        }
        
        syncToCode()
        
        // 自动跳到下一格
        if !filtered.isEmpty && index < 5 {
            focusedIndex = index + 1
        }
        
        // 6 位填满自动提交
        if code.count == 6 {
            onComplete()
        }
    }
    
    private func handleDelete(at index: Int) {
        if digits[index].isEmpty && index > 0 {
            focusedIndex = index - 1
            digits[index - 1] = ""
        } else {
            digits[index] = ""
        }
        syncToCode()
    }
    
    
    private func fillDigits(from text: String, startingAt start: Int) {
        for (offset, char) in text.enumerated() {
            let idx = start + offset
            if idx < 6 {
                digits[idx] = String(char)
            }
        }
        syncToCode()
        let nextFocus = min(start + text.count, 5)
        focusedIndex = nextFocus
        if code.count == 6 {
            onComplete()
        }
    }
    
    private func syncToCode() {
        code = digits.joined()
    }
    
    private func syncFromCode() {
        let chars = Array(code)
        for i in 0..<6 {
            digits[i] = i < chars.count ? String(chars[i]) : ""
        }
    }
}

struct OTPDigitBox: View {
    @Binding var digit: String
    var isFocused: Bool
    
    var body: some View {
        TextField("", text: $digit)
            .frame(width: 44, height: 52)
            .multilineTextAlignment(.center)
            .font(.system(size: 24, weight: .medium, design: .rounded))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isFocused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isFocused ? 2 : 1)
            )
    }
}
