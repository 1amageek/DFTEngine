import Foundation

public enum DFTReleaseEligibilityError: Error, LocalizedError, Sendable, Hashable {
    case runIDMismatch(expected: String, actual: String)
    case executionNotCompleted(String)
    case invalidExecutionMetadata(String)
    case invalidArtifactReference(String)
    case transformedDesignMissing
    case designDiffMissing
    case designDiffInvalid(String)
    case coverageEvidenceMissing
    case coverageIncomplete(String)
    case qualificationInsufficient(DFTQualificationStatus)
    case qualificationProvenanceInvalid(String)
    case processQualificationInvalid(String)
    case downstreamEvidenceMissing(String)
    case approvalRequired
    case approvalRejected
    case invalidReviewContract(String)

    public var errorDescription: String? {
        switch self {
        case .runIDMismatch(let expected, let actual):
            return "DFT release candidate run ID \(actual) does not match expected run ID \(expected)."
        case .executionNotCompleted(let status):
            return "DFT release candidate is not completed: \(status)."
        case .invalidExecutionMetadata(let message):
            return "DFT release execution metadata is invalid: \(message)."
        case .invalidArtifactReference(let message):
            return "DFT release artifact reference is invalid: \(message)."
        case .transformedDesignMissing:
            return "DFT release requires a transformed design artifact."
        case .designDiffMissing:
            return "DFT release requires a design diff artifact."
        case .designDiffInvalid(let message):
            return "DFT release design diff is invalid: \(message)."
        case .coverageEvidenceMissing:
            return "ATPG release requires coverage evidence."
        case .coverageIncomplete(let message):
            return "ATPG coverage is not release eligible: \(message)."
        case .qualificationInsufficient(let status):
            return "DFT qualification status \(status.rawValue) is insufficient for release."
        case .qualificationProvenanceInvalid(let message):
            return "DFT release qualification provenance is invalid: \(message)."
        case .processQualificationInvalid(let message):
            return "DFT process qualification evidence is invalid: \(message)."
        case .downstreamEvidenceMissing(let message):
            return "DFT downstream signoff evidence is incomplete: \(message)."
        case .approvalRequired:
            return "Human approval is required before DFT release."
        case .approvalRejected:
            return "DFT release approval was rejected."
        case .invalidReviewContract(let message):
            return "DFT release review/resume contract is invalid: \(message)."
        }
    }
}
