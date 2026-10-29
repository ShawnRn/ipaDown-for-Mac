#if os(macOS)
import SwiftUI

struct FairPlaySetupView: View {
    @Environment(DecryptionManager.self) private var decryption
    @Environment(DownloadManager.self) private var downloads
    @Environment(AccountManager.self) private var accounts
    @Environment(\.dismiss) private var dismiss
    @State private var setup = FairPlaySetupManager()
    private let steps = ["检查环境", "选择应用", "准备 IPA", "生成模型", "配置完成"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("配置 IPA 砸壳").font(.title2.bold())
            HStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { index in
                    Text("\(index + 1). \(steps[index])")
                        .font(.caption.weight(index == setup.step ? .semibold : .regular))
                        .foregroundStyle(index == setup.step ? Color.accentColor : .secondary)
                    if index < steps.count - 1 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stepContent
                    if setup.isBusy {
                        ProgressView(setup.isGenerating ? "正在生成并验证模型…" : "正在准备…")
                        if let task = setup.downloadTask, task.status != .completed {
                            ProgressView(value: task.progress)
                            Text("\(task.status.displayName) · \(task.sizeProgressString)").font(.caption)
                        }
                    }
                    if !setup.message.isEmpty { Text(setup.message).foregroundStyle(.secondary) }
                    if let error = setup.error {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                        if setup.step == 3 {
                            Text("若提示需要 reference-binary，可在下方选择官方说明要求的精确参考文件后重试。")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("选择参考文件…") { setup.chooseReference() }
                                .disabled(setup.isBusy)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button("关闭") { dismiss() }.disabled(setup.isBusy)
                Spacer()
                if setup.step > 0 && setup.step < 4 {
                    Button("上一步") { setup.step -= 1; setup.error = nil; setup.message = "" }
                        .disabled(setup.isBusy)
                }
                if setup.step == 4 {
                    Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
                } else if setup.step == 3 {
                    Button(setup.error == nil ? "授权并自动生成" : "重试生成") {
                        Task { await setup.generate(using: decryption) }
                    }
                    .disabled(setup.isBusy || decryption.isRunning || decryption.isSettingUp)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("下一步") { next() }
                        .disabled(!canContinue || setup.isBusy)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 680, height: 570)
        .interactiveDismissDisabled(setup.isBusy)
        .task {
            setup.selectedAccountEmail = accounts.activeAccount?.email ?? accounts.accounts.first?.email ?? ""
            await setup.scan()
        }
        .onChange(of: setup.selectedApp) { _, _ in
            setup.ipaURL = nil
            setup.downloadTask = nil
            setup.error = nil
            setup.message = ""
        }
    }

    private var canContinue: Bool {
        switch setup.step {
        case 0: return setup.canGenerateOnThisMac && decryption.engineURL != nil
        case 1: return setup.selectedApp != nil && setup.accountConfirmed
        case 2: return setup.ipaURL != nil
        default: return false
        }
    }

    private func next() {
        setup.error = nil
        setup.message = ""
        setup.step += 1
        if setup.step == 2 {
            Task { await setup.prepareIPA(downloads: downloads, accounts: accounts) }
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch setup.step {
        case 0:
            Text("只需配置一次，之后可直接砸壳已下载的 IPA。").font(.headline)
            Label(decryption.engineURL == nil ? "内置工具缺失，请重新构建应用" : "UnfairPlay 已就绪", systemImage: decryption.engineURL == nil ? "xmark.circle" : "checkmark.circle")
            Label(setup.canGenerateOnThisMac ? "当前 Mac 可以尝试生成模型" : "当前环境无法生成模型，请改用受支持的正式版 Apple 芯片 Mac", systemImage: setup.canGenerateOnThisMac ? "checkmark.circle" : "exclamationmark.circle")
            Text("向导会扫描已安装应用、查找或下载匹配 IPA，最后请求系统授权并自动生成私有模型。确切系统兼容性会在生成时由 UnfairPlay 验证。")
            Text("若你已在其他 Mac 生成模型，可关闭向导，直接选择「导入已有模型」。").foregroundStyle(.secondary)
        case 1:
            Text("选择一个从 Mac App Store 安装的 iPhone 或 iPad 应用").font(.headline)
            Text("请先在 Mac App Store 登录与下载 IPA 相同的 Apple 账号，安装应用并打开一次。向导只显示发现授权文件的应用。")
            HStack {
                Button("打开 Mac App Store") { setup.openAppStore() }
                Button("重新检测") { Task { await setup.scan() } }.disabled(setup.isBusy)
                Button("手动选择…") { setup.chooseApp() }.disabled(setup.isBusy)
            }
            if setup.apps.isEmpty {
                Text("尚未找到可用应用。完成安装并打开后，点击「重新检测」。").foregroundStyle(.secondary)
            } else {
                Picker("已安装应用", selection: $setup.selectedApp) {
                    Text("请选择").tag(Optional<FairPlayInstalledApp>.none)
                    ForEach(setup.apps) { app in
                        Text("\(app.name) · \(app.version)").tag(Optional(app))
                    }
                }
                Button("打开所选应用") { setup.openSelectedApp() }
            }
            Toggle("我已确认 Mac App Store 与 IPA 使用同一个 Apple 账号，并已打开所选应用", isOn: $setup.accountConfirmed)
        case 2:
            Text("自动准备匹配的 IPA").font(.headline)
            Text("优先复用同一应用的已有 IPA，核对真实 FairPlay 授权状态。样本无需与 Mac 应用版本完全相同；模型生成后还会自动进行完整解密验证。")
            if !accounts.accounts.isEmpty {
                Picker("下载账号", selection: $setup.selectedAccountEmail) {
                    ForEach(accounts.accounts) { account in Text(account.email).tag(account.email) }
                }.disabled(setup.isBusy)
                HStack {
                    Button("自动查找或下载") { Task { await setup.prepareIPA(downloads: downloads, accounts: accounts) } }
                    Button("选择已有 IPA…") { Task { await setup.chooseIPA() } }
                }.disabled(setup.isBusy)
            } else {
                Text("ipaDown 尚未登录账号，可先选择已有 IPA，或关闭向导去「账号管理」登录。")
                Button("选择已有 IPA…") { Task { await setup.chooseIPA() } }.disabled(setup.isBusy)
            }
            if let ipa = setup.ipaURL {
                Label("IPA 版本匹配检查通过", systemImage: "checkmark.circle")
                Text(ipa.path).font(.caption).textSelection(.enabled)
            }
        case 3:
            Text("授权后自动生成并验证").font(.headline)
            Text("下一步会弹出 macOS 管理员授权窗口。ipaDown 会读取 FairPlay 状态，在本机生成模型，再用匹配 IPA 验证模型；不会上传授权数据，也不会保存管理员密码。")
            Text("生成期间请保持应用运行，等待完成。IPA 越大，验证可能越久。").foregroundStyle(.secondary)
            if let app = setup.selectedApp { LabeledContent("应用", value: "\(app.name) · \(app.version)") }
            if let reference = setup.referenceURL { Text("参考文件：\(reference.lastPathComponent)").font(.caption) }
        default:
            Label("配置完成", systemImage: "checkmark.seal.fill").font(.title3).foregroundStyle(.green)
            Text("模型已保存在 ipaDown 私有数据目录。现在可以在下载列表点击「砸壳」，或选择任意已下载的 IPA。每份 IPA 都会检查授权是否匹配。")
            Text("原始 IPA 会保留，砸壳结果另存为新文件。解密不等于重新签名。").foregroundStyle(.secondary)
        }
    }
}
#endif
