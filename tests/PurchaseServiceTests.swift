// 真实执行 PurchaseService 的重试和错误分类，网络返回为合成 plist。
import Foundation

@MainActor enum AppLogger {
    static var shared: AppLogger.Type { Self.self }
    static func info(_ category: String, _ message: String) {}
    static func success(_ category: String, _ message: String) {}
}
@MainActor enum DeviceIdentifier { static func getOrCreate() -> String { "001122334455" } }
@MainActor enum StoreClient {
    static let appleUserAgent = "test"
    static var responses: [[String: Any]] = []
    static var calls = 0
    static func authHeaders(for account: Account) -> [String: String] { [:] }
    static func postPlist(url: URL, body: [String: Any], headers: [String: String], cookies: [HTTPCookieData], userAgentOverride: String) async throws -> (Data, HTTPURLResponse, [HTTPCookieData]) {
        calls += 1
        guard !responses.isEmpty else { throw IPAError.invalidResponse("不应额外请求认证或许可") }
        return (try PlistHelper.serialize(responses.removeFirst()), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, [])
    }
}
@main struct PurchaseServiceTests {
    @MainActor static func main() async throws {
        var account = Account(email: "test@example.invalid", password: "synthetic", appleId: "synthetic", storeFront: "143441", firstName: "", lastName: "", passwordToken: "synthetic", directoryServicesId: "1", cookies: [])
        // 已持有许可的账号仍能继续下载；既支持字符串码，也支持 plist 整数码。
        for code: Any in ["5002", 5002, "2040"] {
            StoreClient.responses = [["failureType": code, "customerMessage": "An unknown error has occurred"]]
            StoreClient.calls = 0
            try await PurchaseService.purchase(account: &account, appId: 123)
            precondition(StoreClient.calls == 1)
        }
        StoreClient.responses = [["failureType": "2034"]]
        do {
            try await PurchaseService.purchase(account: &account, appId: 123)
            fatalError("真正失效的 Token 不可当作成功")
        } catch IPAError.tokenExpired { }
        StoreClient.responses = [["failureType": "2059"], ["jingleDocType": "purchaseSuccess", "status": 0]]
        StoreClient.calls = 0
        try await PurchaseService.purchase(account: &account, appId: 123)
        precondition(StoreClient.calls == 2)
        StoreClient.responses = [["failureType": "9999", "customerMessage": "Store unavailable"]]
        do {
            try await PurchaseService.purchase(account: &account, appId: 123)
            fatalError("其他商店错误不可当作成功")
        } catch IPAError.purchaseFailed(let message) { precondition(message == "Store unavailable") }
        print("PASS: owned license 5002/2040, numeric plist code, real token expiry, pricing fallback, other errors")
    }
}
