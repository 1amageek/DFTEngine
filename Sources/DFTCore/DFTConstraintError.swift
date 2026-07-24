import Foundation

public enum DFTConstraintError: Error, LocalizedError, Sendable, Hashable {
    case invalidPath(String)
    case readFailed(String)
    case identityMismatch(String)
    case modeMissing
    case clockMissing(String)
    case testSignalNotAsserted(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            "DFT constraint path is invalid: \(path)."
        case .readFailed(let message):
            "DFT constraints could not be read: \(message)."
        case .identityMismatch(let path):
            "DFT constraint artifact identity does not match \(path)."
        case .modeMissing:
            "DFT constraints contain no declared analysis mode."
        case .clockMissing(let signal):
            "DFT constraints do not declare clock \(signal)."
        case .testSignalNotAsserted(let signal):
            "DFT constraints do not assert test signal \(signal)."
        }
    }
}
