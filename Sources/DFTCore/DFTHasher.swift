import CircuiteFoundation
import Foundation

public struct DFTHasher: Sendable {
    public init() {}

    public func sha256(data: Data) -> String {
        do {
            return try SHA256ContentDigester().digest(data: data).hexadecimalValue
        } catch {
            return ""
        }
    }
}
