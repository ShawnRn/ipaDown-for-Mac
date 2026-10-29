import Foundation
@main struct FairPlaySINFSelectorTests {
    static func main() throws {
        func atom(_ name: String, _ body: Data) -> Data {
            let count = UInt32(body.count + 8)
            return Data([UInt8(count >> 24), UInt8((count >> 16) & 255), UInt8((count >> 8) & 255), UInt8(count & 255)]) + Data(name.utf8) + body
        }
        func license(_ key: UInt8) -> Data {
            atom("sinf", atom("schi", atom("user", Data([0,0,0,1])) + atom("key ", Data([0,0,0,key]))))
        }
        let a = try FairPlaySINFSelector.parse(license(2))
        let b = try FairPlaySINFSelector.parse(license(2))
        let c = try FairPlaySINFSelector.parse(license(3))
        precondition(a == b && a != c)
        for bad in [Data(), Data([0,0,0,0]), license(2).dropLast(), atom("sinf", Data())] {
            do { _ = try FairPlaySINFSelector.parse(Data(bad)); fatalError("Malformed license accepted") }
            catch is IPAError { }
        }
        print("PASS: matching and mismatching authorization, malformed and truncated SINF")
    }
}
