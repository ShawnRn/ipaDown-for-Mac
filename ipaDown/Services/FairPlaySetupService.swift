#if os(macOS)
import Foundation
import ZIPFoundation

nonisolated enum FairPlaySetupService {
    static func installedApp(at url: URL) throws -> FairPlayInstalledApp {
        let fm = FileManager.default
        var inner = url
        let wrapper = url.appendingPathComponent("Wrapper", isDirectory: true)
        if fm.fileExists(atPath: wrapper.path) {
            guard let app = try fm.contentsOfDirectory(at: wrapper, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
                throw IPAError.decryptionFailed("该应用未包含有效的 iPhone / iPad 应用。")
            }
            inner = app
        }
        let data = try Data(contentsOf: inner.appendingPathComponent("Info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundle = info["CFBundleIdentifier"] as? String,
              let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String,
              let platforms = info["CFBundleSupportedPlatforms"] as? [String], platforms.contains("iPhoneOS") else {
            throw IPAError.decryptionFailed("请选择从 Mac App Store 安装的 iPhone / iPad 应用。")
        }
        let licenses = try fm.contentsOfDirectory(at: inner.appendingPathComponent("SC_Info"), includingPropertiesForKeys: nil)
        guard licenses.contains(where: { $0.pathExtension == "sinf" }) else {
            throw IPAError.decryptionFailed("未发现应用授权，请在 Mac App Store 安装并打开该应用一次。")
        }
        return FairPlayInstalledApp(url: url, name: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent, bundleID: bundle, version: version, build: build)
    }

    @concurrent
    static func scanApplications() async -> [FairPlayInstalledApp] {
        let roots = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        return roots.flatMap { root in
            ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "app" }
                .compactMap { try? installedApp(at: $0) }
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @concurrent
    static func validateIPA(_ url: URL, app: FairPlayInstalledApp) async throws {
        let archive = try Archive(url: url, accessMode: .read)
        guard let entry = archive.first(where: {
            let parts = $0.path.split(separator: "/")
            return parts.count == 3 && parts[0] == "Payload" && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
        }) else { throw IPAError.decryptionFailed("IPA 中缺少主应用 Info.plist。") }
        guard entry.uncompressedSize <= 4 * 1024 * 1024 else { throw IPAError.decryptionFailed("IPA 元数据过大。") }
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            guard data.count + chunk.count <= 4 * 1024 * 1024 else { throw IPAError.decryptionFailed("IPA 元数据过大。") }
            data.append(chunk)
        }
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == app.bundleID,
              let executable = info["CFBundleExecutable"] as? String else {
            throw IPAError.decryptionFailed("IPA 与所选 Mac 应用的 Bundle ID 不一致。")
        }
        var inner = app.url
        let wrapper = inner.appendingPathComponent("Wrapper")
        if FileManager.default.fileExists(atPath: wrapper.path) {
            guard let found = try FileManager.default.contentsOfDirectory(at: wrapper, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
                throw IPAError.decryptionFailed("Mac 应用包装目录无效。")
            }
            inner = found
        }
        let licenses = try FileManager.default.contentsOfDirectory(at: inner.appendingPathComponent("SC_Info"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "sinf" }
        guard licenses.count == 1 else { throw IPAError.decryptionFailed("Mac 应用授权文件不唯一。") }
        let installedSelector = try FairPlaySINFSelector.parse(Data(contentsOf: licenses[0]))
        let root = String(entry.path.dropLast("Info.plist".count))
        guard let license = archive[root + "SC_Info/" + executable + ".sinf"], license.uncompressedSize <= 4 * 1024 * 1024 else {
            throw IPAError.decryptionFailed("IPA 缺少有效的主应用 SINF 授权文件。")
        }
        var sinf = Data()
        _ = try archive.extract(license) { chunk in
            guard sinf.count + chunk.count <= 4 * 1024 * 1024 else { throw IPAError.decryptionFailed("授权文件过大。") }
            sinf.append(chunk)
        }
        guard try FairPlaySINFSelector.parse(sinf) == installedSelector else {
            throw IPAError.decryptionFailed("IPA 与 Mac 应用的 FairPlay 授权状态不一致，请确认使用同一账号及授权状态。")
        }
    }

    /// 只有这一步请求 macOS 管理员授权；不收集或保存管理员密码。
    @concurrent
    static func generateModel(engine: URL, app: URL, ipa: URL, models: URL, reference: URL?, user: String, uid: UInt32, gid: UInt32) async throws {
        // 管理员权限不等于 Downloads 的 TCC 授权。由已有读取权限的
        // ipaDown 进程先暂存，再让提权工具只访问应用自己的私有目录。
        let fm = FileManager.default
        let work = models.deletingLastPathComponent().appendingPathComponent("setup-input-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: work) }
        let stagedIPA = work.appendingPathComponent("sample.ipa")
        let access = ipa.startAccessingSecurityScopedResource()
        defer { if access { ipa.stopAccessingSecurityScopedResource() } }
        try fm.copyItem(at: ipa, to: stagedIPA)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stagedIPA.path)
        var stagedReference: URL?
        if let reference {
            let access = reference.startAccessingSecurityScopedResource()
            defer { if access { reference.stopAccessingSecurityScopedResource() } }
            let destination = work.appendingPathComponent("fairplayd.arm64e")
            try fm.copyItem(at: reference, to: destination)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            stagedReference = destination
        }
        var command = "SUDO_USER=\(quote(user)) SUDO_UID=\(uid) SUDO_GID=\(gid) "
        command += [engine.path, "setup", "--app", app.path, "--ipa", stagedIPA.path, "--model-dir", models.path].map(quote).joined(separator: " ")
        if let stagedReference { command += " --reference-binary " + quote(stagedReference.path) }
        let script = "do shell script \(appleScriptLiteral(command)) with administrator privileges with prompt \(appleScriptLiteral("ipaDown 需要读取本机 FairPlay 授权状态，以生成私有解密模型。"))"
        let log = models.deletingLastPathComponent().appendingPathComponent("setup-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: log) }
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let data = try Data(contentsOf: log)
        guard process.terminationStatus == 0,
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any], result["success"] as? Bool == true else {
            let details = String(decoding: data.suffix(8192), as: UTF8.self)
            if details.contains("(-128)") { throw IPAError.decryptionFailed("已取消系统授权，可点击重试。") }
            throw IPAError.decryptionFailed("模型生成未完成。请检查账号、系统版本及参考文件。\n\(details)")
        }
    }

    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleScriptLiteral(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
}
#endif
