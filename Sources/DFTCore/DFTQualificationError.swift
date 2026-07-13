import Foundation

public enum DFTQualificationError: Error, LocalizedError, Sendable, Hashable {
    case invalidEvidence(String)
    case processMismatch(expected: String, actual: String)
    case pdkMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .invalidEvidence(let message):
            return "DFT qualification evidence is invalid: \(message)"
        case .processMismatch(let expected, let actual):
            return "DFT qualification process \(actual) does not match expected process \(expected)."
        case .pdkMismatch(let expected, let actual):
            return "DFT qualification PDK digest \(actual) does not match expected digest \(expected)."
        }
    }
}
