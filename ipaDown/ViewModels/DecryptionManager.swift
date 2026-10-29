#if os(macOS)
import AppKit
import Observation
import CryptoKit
import UniformTypeIdentifiers

@MainActor @Observable
final class DecryptionManager {
    private(set) var isRunning = false
    var isSettingUp = false
    private(set) var inputURL: URL?
    private(set) var outputURL: URL?
    private(set) var modelCount = 0
    private(set) var status = "选择已下载的 IPA，另存为砸壳后的文件。"
    var errorMessage: String?
    @ObservationIgnored private var operation: Task<Void, Never>?

    var engineURL: URL? {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/unfairplay")
        return FileManager.default.isExecutableFile(atPath: helper.path) ? helper : nil
    }

    var isReady: Bool { engineURL != nil && modelCount > 0 }

    private var modelDirectory: URL {
        get throws {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return support.appendingPathComponent("ipaDown/UnfairPlay/models", isDirectory: true)
        }
    }

    init() { refreshModels() }

    func refreshModels() {
        do {
            let directory = try prepareModelDirectory()
            modelCount = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
                .filter { $0.pathExtension.lowercased() == "bin" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.count
        } catch { errorMessage = error.localizedDescription }
    }

    func prepareModelDirectory() throws -> URL {
        let directory = try modelDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        return directory
    }

    func importModels() {
        guard !isRunning, !isSettingUp else { return }
        let panel = NSOpenPanel()
        panel.title = "导入 FairPlay 私有模型"
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data]
        guard panel.runModal() == .OK else { return }
        do {
            let directory = try prepareModelDirectory()
            for source in panel.urls {
                let data = try Data(contentsOf: source)
                // 同上游模型解析器：仅接受已知模型信封，不执行导入内容。
                let magic = String(decoding: data.prefix(8), as: UTF8.self)
                guard data.count >= 16, ["FPSENR1\0", "FPSENR2\0", "FPSENR3\0", "FPS26A4\0"].contains(magic) else {
                    throw IPAError.decryptionFailed("\(source.lastPathComponent) 不是受支持的 UnfairPlay 模型。")
                }
                // 模型注册目录要求 selector，旧版 v1 需先在上游升级。
                guard magic == "FPSENR2\0" || magic == "FPSENR3\0" else {
                    throw IPAError.decryptionFailed("请使用 UnfairPlay setup 生成第 2 或第 3 版模型。")
                }
                let expectedBytes = magic == "FPSENR2\0" ? 4184 : 8708
                guard data.count == expectedBytes else {
                    throw IPAError.decryptionFailed("模型文件不完整或版本不受支持。")
                }
                // setup 和手动导入可以使用不同文件名，按内容避免重复注册。
                let existing = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                if existing.contains(where: { $0.pathExtension == "bin" && (try? Data(contentsOf: $0)) == data }) { continue }
                let destination = directory.appendingPathComponent(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + ".bin")
                try data.write(to: destination, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            }
            refreshModels()
        } catch { errorMessage = error.localizedDescription; refreshModels() }
    }

    func chooseIPA() {
        guard !isRunning, !isSettingUp else { return }
        let panel = NSOpenPanel()
        panel.title = "选择要砸壳的 IPA"
        panel.allowedContentTypes = [UTType(filenameExtension: "ipa") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectInput(url)
    }

    func selectInput(_ url: URL) {
        guard !isRunning, !isSettingUp else { return }
        inputURL = url
        outputURL = nil
        errorMessage = nil
        status = "已选择 IPA，砸壳后将另存为新文件。"
    }

    func start() {
        guard !isRunning, !isSettingUp, let input = inputURL else { return }
        refreshModels()
        guard let engine = engineURL, modelCount > 0 else {
            errorMessage = "请先完成模型配置，并确认此版本内置了 UnfairPlay。"
            return
        }
        let panel = NSSavePanel()
        panel.title = "另存砸壳后的 IPA"
        panel.allowedContentTypes = [UTType(filenameExtension: "ipa") ?? .data]
        panel.directoryURL = input.deletingLastPathComponent()
        panel.nameFieldStringValue = input.deletingPathExtension().lastPathComponent + ".decrypted.ipa"
        guard panel.runModal() == .OK, let output = panel.url else { return }
        do {
            let models = try prepareModelDirectory()
            isRunning = true
            outputURL = nil
            errorMessage = nil
            status = "正在砸壳，请保持应用运行…"
            operation = Task {
                defer { isRunning = false; operation = nil }
                do {
                    try await DecryptionService.decrypt(engine: engine, models: models, input: input, output: output)
                    outputURL = output
                    status = "砸壳完成，原始 IPA 已保留。"
                } catch is CancellationError {
                    status = "已取消砸壳，原始 IPA 已保留。"
                } catch {
                    errorMessage = error.localizedDescription
                    status = "砸壳失败，原始 IPA 已保留。"
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func cancel() { operation?.cancel() }

    func revealOutput() {
        if let outputURL { NSWorkspace.shared.activateFileViewerSelecting([outputURL]) }
    }

    func revealModels() {
        do { NSWorkspace.shared.open(try prepareModelDirectory()) }
        catch { errorMessage = error.localizedDescription }
    }

    func clearModels() {
        guard !isRunning, !isSettingUp else { return }
        do {
            let directory = try prepareModelDirectory()
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "bin" {
                try FileManager.default.removeItem(at: url)
            }
            refreshModels()
        } catch { errorMessage = error.localizedDescription }
    }

}
#endif
