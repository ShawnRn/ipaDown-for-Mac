#if os(macOS)
import Foundation
import CryptoKit

/// 固定版本的 Store 引擎通过私有文件句柄接收凭据，独立保存每个账号的认证状态。
enum StoreBridge {
    nonisolated struct Request: Encodable, Sendable {
        var Operation: String
        var Directory = ""
        var Email: String
        var Password = ""
        var Code = ""
        var AppID: Int64 = 0
        var VersionID = ""
    }

    nonisolated struct StoreAccount: Decodable, Sendable {
        var email: String
        var passwordToken: String
        var directoryServicesIdentifier: String
        var name: String?
        var storeFront: String?
    }

    nonisolated struct Response: Decodable, Sendable {
        var account: StoreAccount?
        var plist: Data?
        var error: String?
        var code: String?
    }

    nonisolated static func sessionDirectory(email: String) throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ipaDown/StoreSessions", isDirectory: true)
        let hash = SHA256.hash(data: Data(email.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(hash, isDirectory: true)
    }

    static func authenticate(email: String, password: String, code: String) async throws -> Account {
        AppLogger.shared.info("登录", "正在准备新版 Apple 认证；首次使用需下载组件，可能耗时数分钟…")
        let response = try await execute(Request(Operation: "login", Email: email, Password: password, Code: code))
        guard let result = response.account, !result.passwordToken.isEmpty,
              !result.directoryServicesIdentifier.isEmpty else {
            throw IPAError.authenticationFailed("Apple 未返回完整账号信息")
        }
        return Account(email: email, password: password, appleId: result.email,
                       storeFront: result.storeFront?.components(separatedBy: "-").first ?? "",
                       firstName: result.name ?? "", lastName: "",
                       passwordToken: result.passwordToken,
                       directoryServicesId: result.directoryServicesIdentifier, cookies: [])
    }

    static func downloadData(account: Account, appId: Int64, versionId: String) async throws -> Data {
        let response = try await execute(Request(Operation: "downloadInfo", Email: account.email, AppID: appId, VersionID: versionId))
        guard let data = response.plist else { throw IPAError.invalidResponse("新版下载引擎未返回下载信息") }
        return data
    }

    static func purchase(account: Account, appId: Int64) async throws {
        _ = try await execute(Request(Operation: "purchase", Email: account.email, AppID: appId))
    }

    @concurrent
    private static func execute(_ input: Request) async throws -> Response {
        try Task.checkCancellation()
        let fm = FileManager.default
        let engine = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/storebridge")
        guard fm.isExecutableFile(atPath: engine.path) else {
            throw IPAError.fileError("缺少新版 Store 引擎，请安装完整版本")
        }
        var request = input
        let session = try sessionDirectory(email: input.Email)
        request.Directory = session.path
        if input.Operation != "login", !fm.fileExists(atPath: session.appendingPathComponent("session.json").path) {
            throw IPAError.tokenExpired
        }
        let root = session.deletingLastPathComponent().deletingLastPathComponent()
        let work = root.appendingPathComponent(".store-request-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: work) }
        let inputURL = work.appendingPathComponent("input.json")
        let outputURL = work.appendingPathComponent("output.json")
        fm.createFile(atPath: inputURL.path, contents: try JSONEncoder().encode(request), attributes: [.posixPermissions: 0o600])
        fm.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let reader = try FileHandle(forReadingFrom: inputURL)
        let writer = try FileHandle(forWritingTo: outputURL)
        defer { try? reader.close(); try? writer.close() }
        var environment = ProcessInfo.processInfo.environment
        environment["GODEBUG"] = "netdns=cgo"
        environment["IPADOWN_STORE_CACHE"] = root.appendingPathComponent("StoreRuntime", isDirectory: true).path
        let process = UnfairPlayProcess(executable: engine, arguments: [], log: writer, input: reader, environment: environment)
        let status = try await process.run()
        guard status == 0 else { throw IPAError.networkError("新版 Store 引擎异常退出（\(status)）") }
        let response = try JSONDecoder().decode(Response.self, from: Data(contentsOf: outputURL))
        switch response.code {
        case "codeRequired": throw IPAError.codeRequired
        case "tokenExpired": throw IPAError.tokenExpired
        case "licenseRequired": throw IPAError.licenseRequired
        default: break
        }
        if let error = response.error { throw IPAError.networkError(error) }
        return response
    }
}
#endif
