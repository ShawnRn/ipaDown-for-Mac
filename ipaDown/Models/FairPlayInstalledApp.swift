#if os(macOS)
import Foundation

nonisolated struct FairPlayInstalledApp: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    let build: String
}
#endif
