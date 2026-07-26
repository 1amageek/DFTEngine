import Foundation

public enum DFTMemoryBISTCellMappingError: Error, LocalizedError, Sendable, Hashable {
    case loaderUnavailable
    case invalidPath(String)
    case readFailed(String)
    case identityMismatch(String)
    case decodeFailed(String)
    case contentMismatch

    public var errorDescription: String? {
        switch self {
        case .loaderUnavailable:
            "Memory-BIST cell mapping loading is unavailable."
        case .invalidPath(let path):
            "Memory-BIST cell mapping path is invalid: \(path)."
        case .readFailed(let message):
            "Memory-BIST cell mapping could not be read: \(message)"
        case .identityMismatch(let path):
            "Memory-BIST cell mapping artifact identity does not match \(path)."
        case .decodeFailed(let message):
            "Memory-BIST cell mapping could not be decoded: \(message)"
        case .contentMismatch:
            "Memory-BIST inline mapping does not match its immutable mapping artifact."
        }
    }
}
