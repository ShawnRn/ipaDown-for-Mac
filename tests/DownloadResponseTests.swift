import Foundation

@MainActor enum AppLogger {
    static var shared: AppLogger.Type { Self.self }
    static func info(_ category: String, _ message: String) {}
    static func success(_ category: String, _ message: String) {}
    static func warning(_ category: String, _ message: String) {}
}
@MainActor enum StoreBridge {
    static var response: [String: Any] = [:]
    static func downloadData(account: Account, appId: Int64, versionId: String) async throws -> Data {
        try PlistHelper.serialize(response)
    }
}

@main struct DownloadResponseTests {
    @MainActor static func main() async throws {
        let account = Account(email: "test@example.invalid", password: "", appleId: "", storeFront: "143465", firstName: "", lastName: "", passwordToken: "", directoryServicesId: "1", cookies: [])
        let signature = Data([0, 1, 2, 255])
        for identifier: Int64? in [nil, 0, 42] {
            var sinf: [String: Any] = ["sinf": signature]
            if let identifier { sinf["id"] = identifier }
            StoreBridge.response = ["songList": [["URL": "https://example.invalid/app.ipa", "sinfs": [sinf]]]]
            let info = try await DownloadService.requestDownload(account: account, appId: 123, versionId: "456")
            precondition(info.sinfs.count == 1, "有效签名不能因为编号缺省而丢失")
            precondition(info.sinfs[0].id == identifier ?? 0)
            precondition(info.sinfs[0].data == signature)
        }
        StoreBridge.response = ["failureType": "2042"]
        do {
            _ = try await DownloadService.requestDownload(account: account, appId: 123)
            fatalError("失效会话必须触发刷新")
        } catch IPAError.tokenExpired { }
        print("PASS: omitted/zero/nonzero SINF identifiers retain signature data; token expiry propagates")
    }
}
