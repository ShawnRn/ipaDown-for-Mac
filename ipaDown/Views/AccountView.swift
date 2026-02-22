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
    @State private var showingAddAccount = false
    
    var body: some View {
        @Bindable var manager = accountManager
        
        Group {
            if accountManager.accounts.isEmpty {
                ContentUnavailableView(
                    "无保存的账号",
                    systemImage: "person.crop.circle.badge.xmark",
                    description: Text("请点击右上角绑定你的 Apple 账户")
                )
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(accountManager.accounts) { account in
                            accountCard(account)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("账号管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddAccount = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            #if os(macOS)
            if accountManager.needsTwoFactorCode {
                twoFactorSheet
            } else {
                macOSLoginSection
            }
            #else
            NavigationStack {
                if accountManager.needsTwoFactorCode {
                    twoFactorSheet
                } else {
                    iOSLoginSection
                }
            }
            // iPad 上使用默认的大尺寸居中浮层，iPhone 上使用半屏弹起
            .presentationDetents(UIDevice.current.userInterfaceIdiom == .pad ? [] : [.medium])
            #endif
        }
        .alert(refreshResultTitle, isPresented: $showingRefreshResult) {
            Button("好", role: .cancel) { }
        } message: {
            Text(refreshResultMessage)
        }
    }
    
    // MARK: - 统一账号卡片
    
    @ViewBuilder
    private func accountCard(_ account: Account) -> some View {
        let isActive = account.id == accountManager.activeAccount?.id
        
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: isActive ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(isActive ? .blue : .secondary)
                    
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
                                .background(isActive ? .blue.opacity(0.1) : .secondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        
                        Text("Store: \(account.storeFront)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                HStack {
                    Text("Apple 账户: \(account.appleId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Spacer(minLength: 16)
                    
                    // 删除按钮
                    Button(role: .destructive) {
                        accountManager.deleteAccount(account)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .padding(.trailing, 8)
                    
                    // 刷新按钮
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
                            ProgressView().controlSize(.small)
                        } else {
                            Text("刷新 Token")
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(isRefreshing)
                    
                    // 切换按钮
                    Button {
                        accountManager.switchAccount(to: account)
                    } label: {
                        Text(isActive ? "当前使用" : "切换")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(isActive || isRefreshing)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isActive ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }
    
    // MARK: - macOS 登录浮层
    
    #if os(macOS)
    private var macOSLoginSection: some View {
        @Bindable var manager = accountManager
        
        return VStack(spacing: 24) {
            HStack(alignment: .top, spacing: 20) {
                // 左侧应用/Apple 图标
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "applelogo")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    // 标题区
                    VStack(alignment: .leading, spacing: 6) {
                        Text("登录你的 Apple 账户")
                            .font(.headline)
                        
                        Text("输入 Apple 账户的电子邮件和密码。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    // 输入框组
                    VStack(spacing: 0) {
                        TextField("Apple 账户", text: $manager.loginEmail)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                            .onSubmit { performLogin() }
                        
                        Divider()
                        
                        SecureField("密码", text: $manager.loginPassword)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .textContentType(.password)
                            .onSubmit { performLogin() }
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    
                    if let error = accountManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            
            // 底部按钮区
            HStack {
                Spacer()
                
                Button("取消") {
                    showingAddAccount = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button {
                    performLogin()
                } label: {
                    if accountManager.isLoggingIn {
                        ProgressView().controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Text("登录")
                            .padding(.horizontal, 8)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(accountManager.isLoggingIn || accountManager.loginEmail.isEmpty || accountManager.loginPassword.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
    #endif
    
    // MARK: - iOS 原生风格登录表单
    
    #if os(iOS)
    private var iOSLoginSection: some View {
        @Bindable var manager = accountManager
        
        return Form {
            Section {
                HStack {
                    Text("Apple 账户")
                        .frame(width: 80, alignment: .leading)
                    
                    TextField("Apple 账户", text: $manager.loginEmail)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .onSubmit { performLogin() }
                }
                
                HStack {
                    Text("密码")
                        .frame(width: 80, alignment: .leading)
                    
                    SecureField("必填", text: $manager.loginPassword)
                        .textContentType(.password)
                        .onSubmit { performLogin() }
                }
            }
            
            if let error = accountManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .listRowBackground(Color.clear)
            }
            
            Section {
                Button {
                    performLogin()
                } label: {
                    HStack {
                        Spacer()
                        if accountManager.isLoggingIn {
                            ProgressView()
                        } else {
                            Text("登录")
                                .foregroundStyle((accountManager.loginEmail.isEmpty || accountManager.loginPassword.isEmpty) ? Color.secondary : Color.blue)
                        }
                        Spacer()
                    }
                }
                .disabled(accountManager.isLoggingIn || accountManager.loginEmail.isEmpty || accountManager.loginPassword.isEmpty)
            } footer: {
                Text("Apple 账户可用于登录 Apple 的所有服务。")
            }
        }
        .navigationTitle("帐户")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    showingAddAccount = false
                }
                .font(.headline)
            }
        }
    }
    #endif
    
    private func performLogin() {
        guard !accountManager.isLoggingIn else { return }
        Task {
            await accountManager.login()
            if accountManager.errorMessage == nil && !accountManager.needsTwoFactorCode {
                showingAddAccount = false
            }
        }
    }
    
    // MARK: - 两步验证
    
    private var twoFactorSheet: some View {
        @Bindable var manager = accountManager
        
        return VStack(spacing: 24) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
                .symbolEffect(.bounce, value: accountManager.needsTwoFactorCode)
            
            VStack(spacing: 8) {
                Text("双重验证")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("请输入发送到你设备上的 6 位验证码")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Apple 风格 6 位验证码输入
            OTPInputView(code: $manager.twoFactorCode, onComplete: {
                submitTwoFactor()
            })
            .padding(.vertical, 10)
            
            if let error = accountManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            
            HStack(spacing: 16) {
                Button("取消") {
                    accountManager.needsTwoFactorCode = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                
                Spacer()
                
                Button("验证") {
                    submitTwoFactor()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(accountManager.twoFactorCode.count < 6 || accountManager.isLoggingIn)
            }
        }
        #if os(macOS)
        .padding(40)
        .background(Color.platformWindowBackground)
        .frame(width: 440)
        #else
        .padding(32)
        .frame(maxWidth: 400)
        #endif
    }
    
    private func submitTwoFactor() {
        guard accountManager.twoFactorCode.count == 6, !accountManager.isLoggingIn else { return }
        Task {
            await accountManager.submitTwoFactorCode()
            if accountManager.errorMessage == nil && !accountManager.needsTwoFactorCode {
                showingAddAccount = false
            }
        }
    }
}

// MARK: - Apple 风格 6 位 OTP 输入

struct OTPInputView: View {
    @Binding var code: String
    var onComplete: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack {
            // 显示给用户看的 6 个盒子
            HStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    box(at: index)
                }
            }
            
            // 隐藏的真实输入框覆盖在最上层，充当巨大点击热区
            TextField("", text: $code)
                #if os(iOS)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                #endif
                .focused($isFocused)
                // 使其文字与光标完全透明
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: code) { _, newValue in
                    // 只保留前 6 位数字
                    let filtered = String(newValue.filter { $0.isNumber }.prefix(6))
                    if filtered != newValue {
                        code = filtered
                    }
                    if filtered.count == 6 {
                        // 延迟一丁点确保状态更新
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onComplete()
                        }
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 强制重新激活焦点：解决 iPad 等设备上手动收起键盘后，isFocused 状态未重置
            // 导致即使重新点击 TextField 也无法通知系统唤起键盘的 SwiftUI 漏洞
            if isFocused {
                isFocused = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFocused = true
                }
            } else {
                isFocused = true
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isFocused = true
            }
        }
    }
    
    @ViewBuilder
    private func box(at index: Int) -> some View {
        let char = getChar(at: index)
        let isActive = isFocused && (code.count == index || (code.count == 6 && index == 5))
        
        VStack(spacing: 0) {
            Text(char)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .frame(width: 46, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.platformControlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isActive ? Color.blue : Color.secondary.opacity(0.2), lineWidth: isActive ? 2 : 1)
                )
                // 聚焦时的微光效果
                .shadow(color: isActive ? Color.blue.opacity(0.15) : Color.clear, radius: 4, x: 0, y: 0)
            
            // 下划线分隔（可选，Apple 风格通常不需要，但增加辨识度）
            if index == 2 {
                // 这里如果不想要下划线可以去掉，原代码有个 "-" 符号
            }
        }
        // 在第 2 和第 3 个盒子后加一点间距
        .padding(.trailing, index == 2 ? 8 : 0)
    }
    
    private func getChar(at index: Int) -> String {
        if index < code.count {
            let idx = code.index(code.startIndex, offsetBy: index)
            return String(code[idx])
        }
        return ""
    }
}
