// 仅使用合成文件和模拟进程，不读取账号、不请求管理员权限。
import Foundation

@main
struct DecryptionServiceTests {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "DecryptionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ipaDown 测试 ' \(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let input = root.appendingPathComponent("original ' $x.ipa")
        let output = root.appendingPathComponent("output.ipa")
        let models = root.appendingPathComponent("models")
        let engine = root.appendingPathComponent("fake engine")
        try Data("encrypted-original".utf8).write(to: input)
        try fm.createDirectory(at: models, withIntermediateDirectories: false)
        func installEngine(_ body: String) throws {
            try Data(("#!/bin/sh\n" + body).utf8).write(to: engine)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.path)
        }
        let reportGuard = "args=\" $* \"\ncase \"$args\" in *' --report '*) ;; *) echo 'missing isolated report' >&2; exit 9;; esac\n"
        let parseOutput = reportGuard + "while [ $# -gt 0 ]; do if [ \"$1\" = '--output' ]; then shift; out=\"$1\"; fi; shift; done\n"
        try installEngine(parseOutput + "printf 'plaintext' > \"$out\"\n")
        try await DecryptionService.decrypt(engine: engine, models: models, input: input, output: output)
        try require(try String(contentsOf: output, encoding: .utf8) == "plaintext", "success output")
        try require(try String(contentsOf: input, encoding: .utf8) == "encrypted-original", "original preserved")
        do {
            try await DecryptionService.decrypt(engine: engine, models: models, input: input, output: output)
            throw NSError(domain: "ExpectedCollision", code: 1)
        } catch let error as IPAError {
            try require(error.localizedDescription.contains("已存在"), "collision rejects")
        }
        try fm.removeItem(at: output)
        try installEngine(parseOutput + "printf 'partial' > \"$out\"\nprintf 'model mismatch' >&2\nexit 1\n")
        do {
            try await DecryptionService.decrypt(engine: engine, models: models, input: input, output: output)
            throw NSError(domain: "ExpectedFailure", code: 1)
        } catch let error as IPAError {
            try require(error.localizedDescription.contains("model mismatch"), "engine diagnostic surfaced")
        }
        try require(!fm.fileExists(atPath: output.path), "no partial output")
        // 输出超过管道容量，确认不会因无人读取 stdout/stderr 而死锁。
        try installEngine(parseOutput + "dd if=/dev/zero bs=1024 count=256 1>&2 2>/dev/null\nprintf 'plaintext' > \"$out\"\n")
        try await DecryptionService.decrypt(engine: engine, models: models, input: input, output: output)
        try fm.removeItem(at: output)
        try installEngine(parseOutput + "printf 'partial' > \"$out\"\nwhile :; do :; done\n")
        let task = Task { try await DecryptionService.decrypt(engine: engine, models: models, input: input, output: output) }
        try await Task.sleep(for: .milliseconds(350))
        task.cancel()
        do { try await task.value; throw NSError(domain: "ExpectedCancellation", code: 1) }
        catch is CancellationError { }
        try require(!fm.fileExists(atPath: output.path), "cancellation publishes nothing")
        let remaining = try fm.contentsOfDirectory(atPath: root.path)
        try require(!remaining.contains(where: { $0.hasPrefix(".ipaDown-decrypt-") }), "temporary plaintext cleaned")
        try require(try String(contentsOf: input, encoding: .utf8) == "encrypted-original", "original remains after all failure paths")
        print("PASS: success, original preservation, no overwrite, failure cleanup, large diagnostics, cancellation")
    }
}
