#if os(macOS)
import Foundation

/// 只读取授权选择器；不输出账号标识，不替代上游的密码学验证。
nonisolated struct FairPlaySINFSelector: Equatable, Sendable {
    private let user: Data
    private let key: Data

    static func parse(_ data: Data) throws -> Self {
        func atoms(_ bytes: Data) throws -> [String: Data] {
            let bytes = [UInt8](bytes)
            var result: [String: Data] = [:]
            var cursor = 0
            while cursor < bytes.count {
                guard bytes.count - cursor >= 8 else { throw IPAError.decryptionFailed("SINF 结构不完整。") }
                let size = bytes[cursor..<cursor+4].reduce(0) { ($0 << 8) | Int($1) }
                guard size >= 8, size <= bytes.count - cursor else { throw IPAError.decryptionFailed("SINF 字段范围无效。") }
                let name = String(decoding: bytes[cursor+4..<cursor+8], as: UTF8.self)
                guard result[name] == nil else { throw IPAError.decryptionFailed("SINF 包含重复字段。") }
                result[name] = Data(bytes[cursor+8..<cursor+size])
                cursor += size
            }
            return result
        }
        let roots = try atoms(data)
        guard roots.count == 1, let root = roots["sinf"], let schi = try atoms(root)["schi"] else {
            throw IPAError.decryptionFailed("SINF 缺少授权结构。")
        }
        let fields = try atoms(schi)
        guard let user = fields["user"], user.count == 4, let key = fields["key "], key.count == 4 else {
            throw IPAError.decryptionFailed("SINF 授权选择器无效。")
        }
        return Self(user: user, key: key)
    }
}
#endif
