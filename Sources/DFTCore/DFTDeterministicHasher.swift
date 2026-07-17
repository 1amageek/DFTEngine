import CircuiteFoundation
import Foundation

public struct DFTDeterministicHasher: Sendable {
    public init() {}

    public func digest<T: Encodable>(_ value: T) throws -> String {
        let data = try DFTArtifactJSONEncoder().encode(value)
        return try SHA256ContentDigester().digest(data: data).hexadecimalValue
    }

    public func seed(for value: String) throws -> UInt64 {
        let digest = try SHA256ContentDigester()
            .digest(data: Data(value.utf8))
            .hexadecimalValue
        let prefix = String(digest.prefix(16))
        guard let seed = UInt64(prefix, radix: 16) else {
            throw DFTDeterministicHasherError.invalidDigestPrefix(prefix)
        }
        return seed
    }
}
