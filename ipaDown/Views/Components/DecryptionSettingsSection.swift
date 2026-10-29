#if os(macOS)
import SwiftUI

struct DecryptionSettingsSection: View {
    @Environment(DecryptionManager.self) private var manager
    @State private var confirmRemoval = false
    @State private var showSetup = false

    var body: some View {
        Section("IPA 砸壳 · UnfairPlay") {
            LabeledContent("解密工具", value: manager.engineURL == nil ? "未内置，请重新构建" : "已内置")
            LabeledContent("私有模型", value: "已导入 \(manager.modelCount) 份")
            HStack {
                Button("导入已有模型…") { manager.importModels() }
                Button("刷新") { manager.refreshModels() }
                Button("打开模型目录") { manager.revealModels() }
            }
            .disabled(manager.isRunning || manager.isSettingUp)
            Button(manager.modelCount == 0 ? "开始配置向导…" : "为其他账号配置模型…", systemImage: "wand.and.stars") { showSetup = true }
                .disabled(manager.isRunning || manager.isSettingUp)
                .sheet(isPresented: $showSetup) { FairPlaySetupView() }
            Text("模型保存在 ipaDown 私有数据目录，仅在本机使用。砸壳不会重新签名，也不保证 App 可侧载运行。")
                .font(.caption).foregroundStyle(.secondary)
            Button("移除所有私有模型…", role: .destructive) { confirmRemoval = true }
                .disabled(manager.isRunning || manager.modelCount == 0)
                .confirmationDialog("移除 ipaDown 中的所有私有模型？", isPresented: $confirmRemoval, titleVisibility: .visible) {
                    Button("移除模型", role: .destructive) { manager.clearModels() }
                } message: { Text("保留原始导入文件。之后需要重新导入或初始化才能砸壳。") }
        }
    }
}
#endif
