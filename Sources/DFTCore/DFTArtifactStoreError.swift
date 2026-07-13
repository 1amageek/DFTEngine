import Foundation

public enum DFTArtifactStoreError: Error, LocalizedError, Sendable, Hashable {
    case invalidRunID(String)
    case invalidFileName(String)
    case invalidArtifactID(String)
    case pathOutsideRoot(String)
    case artifactConflict(String)
    case directoryCreationFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRunID(let value):
            return "DFT artifact run ID is unsafe: \(value)."
        case .invalidFileName(let value):
            return "DFT artifact file name is unsafe: \(value)."
        case .invalidArtifactID(let value):
            return "DFT artifact ID is unsafe: \(value)."
        case .pathOutsideRoot(let path):
            return "DFT artifact path resolves outside the configured root: \(path)."
        case .artifactConflict(let path):
            return "DFT artifact path already contains different immutable content: \(path)."
        case .directoryCreationFailed(let message):
            return "DFT artifact directory could not be created: \(message)."
        case .writeFailed(let message):
            return "DFT artifact could not be written: \(message)."
        }
    }
}
