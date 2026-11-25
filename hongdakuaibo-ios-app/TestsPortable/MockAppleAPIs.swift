import Foundation
extension URL {
    func startAccessingSecurityScopedResource() -> Bool { false }
    func stopAccessingSecurityScopedResource() { }
}
final class NSFileCoordinator {
    struct ReadingOptions: OptionSet {
        let rawValue: Int
        init(rawValue: Int) {self.rawValue = rawValue}
    }
    init(filePresenter: AnyObject?) { }
    func coordinate(readingItemAt url: URL, options: ReadingOptions, error: inout NSError?, byAccessor: (URL) -> Void) {byAccessor(url)}
}
enum FileDigest {
    static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        var digest = SHA256()
        digest.update(data: data)
        return digest.finalize().map { String(format:"%02x",$0) }.joined()
    }
}
struct SHA256 {
    var value: UInt64 = 14695981039346656037
    mutating func update(data: Data) { for b in data { value = (value ^ UInt64(b)) &* 1099511628211 } }
    mutating func finalize() -> [UInt8] {
        let v = Array(withUnsafeBytes(of: value.bigEndian, Array.init))
        return v + v + v + v
    }
}
