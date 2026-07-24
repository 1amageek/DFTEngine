import Foundation

public enum DFTResultSemanticValidationError: Error, LocalizedError, Sendable, Hashable {
    case resultNotCompleted
    case artifactIdentityMismatch(String)
    case artifactDecodeFailed(String)
    case semanticMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .resultNotCompleted:
            "DFT semantic validation requires a completed result."
        case .artifactIdentityMismatch(let path):
            "DFT artifact identity does not match retained content at \(path)."
        case .artifactDecodeFailed(let message):
            "DFT artifact could not be decoded: \(message)"
        case .semanticMismatch(let message):
            "DFT semantic evidence is invalid: \(message)"
        }
    }
}
