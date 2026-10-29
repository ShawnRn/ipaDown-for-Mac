#if os(macOS)
import Foundation
import Darwin

/// UnfairPlay 使用独立进程运行；输出先写入私有临时目录，成功后才发布。
enum DecryptionService {
    @concurrent
    static func decrypt(engine: URL, models: URL, input: URL, output: URL) async throws {
        let fm = FileManager.default
        guard input.standardizedFileURL.resolvingSymlinksInPath() != output.standardizedFileURL.resolvingSymlinksInPath(),
              !fm.fileExists(atPath: output.path) else {
            throw IPAError.decryptionFailed("输出文件已存在，请选择新的文件名。")
        }
        guard fm.isReadableFile(atPath: input.path) else {
            throw IPAError.decryptionFailed("原始 IPA 不存在或无法读取。")
        }
        let work = output.deletingLastPathComponent().appendingPathComponent(".ipaDown-decrypt-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: work) }
        let temporaryOutput = work.appendingPathComponent("decrypted.ipa")
        let log = work.appendingPathComponent("engine.log")
        fm.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let logHandle = try FileHandle(forWritingTo: log)
        defer { try? logHandle.close() }
        let process = UnfairPlayProcess(
            executable: engine,
            arguments: ["decrypt", "--input", input.path, "--output", temporaryOutput.path, "--report", work.appendingPathComponent("report.json").path, "--model", models.path],
            log: logHandle
        )
        // 进程结束后才清理临时明文；不经过 shell。
        let status = try await process.run()
        guard status == 0 else {
            let reader = try FileHandle(forReadingFrom: log)
            defer { try? reader.close() }
            let size = try reader.seekToEnd()
            try reader.seek(toOffset: size > 8192 ? size - 8192 : 0)
            let message = String(decoding: try reader.readToEnd() ?? Data(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw IPAError.decryptionFailed("UnfairPlay 未能完成处理。\n\(message.isEmpty ? "UnfairPlay 未正常退出。" : message)")
        }
        let attributes = try fm.attributesOfItem(atPath: temporaryOutput.path)
        guard (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
            throw IPAError.decryptionFailed("UnfairPlay 未生成有效输出。")
        }
        try Task.checkCancellation()
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryOutput.path)
        // moveItem 不覆盖已存在文件，也防止选择文件后出现的同名冲突。
        try fm.moveItem(at: temporaryOutput, to: output)
    }
}
#endif
