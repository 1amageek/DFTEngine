import Foundation

public enum DFTResultValidationError: Error, LocalizedError, Sendable, Hashable {
    case schemaVersionMismatch(expected: Int, actual: Int)
    case runIDMismatch(expected: String, actual: String)
    case provenanceInputMismatch
    case producerIdentityIncomplete
    case artifactInvalid(String)
    case completedPayloadIncomplete(DFTOperation)
    case coverageInvalid(String)

    public var errorDescription: String? {
        switch self {
        case .schemaVersionMismatch(let expected, let actual):
            "DFT result schema version \(actual) does not match \(expected)."
        case .runIDMismatch(let expected, let actual):
            "DFT result run ID \(actual) does not match \(expected)."
        case .provenanceInputMismatch:
            "DFT result provenance does not contain the exact execution input set."
        case .producerIdentityIncomplete:
            "DFT result producer identity is incomplete."
        case .artifactInvalid(let message):
            "DFT result artifact contract is invalid: \(message)"
        case .completedPayloadIncomplete(let operation):
            "Completed DFT result is missing required \(operation.rawValue) outputs."
        case .coverageInvalid(let message):
            "DFT coverage contract is invalid: \(message)"
        }
    }
}
