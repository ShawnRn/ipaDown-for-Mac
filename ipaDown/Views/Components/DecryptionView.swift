#if os(macOS)
import SwiftUI

struct DecryptionView: View {
    @Environment(DecryptionManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showSetup = false

    private var completed: Bool { manager.outputURL != nil && !manager.isRunning }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(manager.isReady ? "已就绪" : "需要首次配置", systemImage: manager.isReady ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("配置…", systemImage: "slider.horizontal.3") { showSettings = true }
                    .labelStyle(.iconOnly).help("管理解密配置")
                    .disabled(manager.isRunning || manager.isSettingUp)
            }
            .padding(.bottom, 28)

            Image(systemName: completed ? "checkmark.circle.fill" : "lock.open")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(completed ? Color.green : Color.accentColor)
                .accessibilityHidden(true)
            Text(completed ? "砸壳完成" : manager.isRunning ? "正在砸壳" : "IPA 砸壳")
                .font(.title2.bold()).padding(.top, 14)
            Text(completed ? "原始文件已保留，新文件已准备好。" : manager.isRunning ? "正在本机处理，可以在后台继续。" : "选择 IPA，在本机解密并另存。")
                .font(.callout).foregroundStyle(.secondary).padding(.top, 6)

            if !manager.isReady && !manager.isRunning {
                Button("开始配置", systemImage: "wand.and.stars") { showSetup = true }
                    .buttonStyle(.borderedProminent).padding(.top, 22)
            }

            if let file = completed ? manager.outputURL : manager.inputURL {
                HStack(spacing: 12) {
                    Image(systemName: "doc.zipper").font(.title2).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.lastPathComponent).font(.callout.weight(.medium)).lineLimit(2)
                        Text(completed ? "已解密的 IPA" : "原始 IPA")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if !manager.isRunning && !completed {
                        Button("更换…") { manager.chooseIPA() }
                    }
                }
                .padding(16)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .help(file.path)
                .padding(.top, 24)
            } else {
                Button { manager.chooseIPA() } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle").font(.title2)
                        Text("选择 IPA 文件…").font(.callout)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.borderless)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 24)
            }

            if manager.isRunning {
                ProgressView().controlSize(.small).padding(.top, 20)
            }
            if let error = manager.errorMessage {
                ScrollView { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 100).padding(.top, 16)
            }
            Spacer(minLength: 24)
            HStack {
                Button(manager.isRunning ? "在后台继续" : "关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if manager.isRunning {
                    Button("取消", role: .destructive) { manager.cancel() }
                } else if completed {
                    Button("处理另一个…") { manager.chooseIPA() }
                    Button("查看文件", systemImage: "folder") { manager.revealOutput() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button("砸壳并另存…") { manager.start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!manager.isReady || manager.inputURL == nil || manager.isSettingUp)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 520, height: manager.errorMessage == nil ? 420 : 520)
        .sheet(isPresented: $showSetup) { FairPlaySetupView() }
        .sheet(isPresented: $showSettings) {
            VStack(spacing: 0) {
                Form { DecryptionSettingsSection() }.formStyle(.grouped)
                HStack { Spacer(); Button("完成") { showSettings = false }.keyboardShortcut(.defaultAction) }.padding(20)
            }.frame(width: 560, height: 470)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { manager.refreshModels() }
        }
    }
}
#endif
