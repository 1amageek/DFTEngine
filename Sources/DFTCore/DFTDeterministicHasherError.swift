import Foundation

public enum DFTDeterministicHasherError: Error, LocalizedError, Sendable, Hashable {
    case invalidDigestPrefix(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidDigestPrefix(prefix):
            return "The SHA-256 digest prefix is not a valid UInt64 value: \(prefix)."
        }
    }
}
