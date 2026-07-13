import Foundation
import XcircuitePackage

public struct DFTDeterministicHasher: Sendable {
    public init() {}

    public func digest<T: Encodable>(_ value: T) throws -> String {
        let data = try DFTArtifactJSONEncoder().encode(value)
        return XcircuiteHasher().sha256(data: data)
    }

    public func seed(for value: String) -> UInt64 {
        let digest = XcircuiteHasher().sha256(data: Data(value.utf8))
        let prefix = String(digest.prefix(16))
        return UInt64(prefix, radix: 16) ?? 0
    }
}
