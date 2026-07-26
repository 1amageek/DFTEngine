import Foundation

public enum DFTRealizedScanATPGRequestBuilderError:
    Error, LocalizedError, Sendable, Hashable
{
    case emptyRunID
    case inputIdentityMismatch(String)
    case scanImplementationDecodeFailed(String)
    case scanImplementationInvalid([String])
    case transformedDesignMismatch
    case processMismatch
    case gateLevelFaultSourceRequired
    case clockIDsInvalid
    case domainClockMappingMismatch
    case unknownClockID(domainID: String, clockID: String)

    public var errorDescription: String? {
        switch self {
        case .emptyRunID:
            return "The realized-scan ATPG run ID must not be empty."
        case .inputIdentityMismatch(let path):
            return "The retained scan implementation does not match \(path)."
        case .scanImplementationDecodeFailed(let message):
            return "The retained scan implementation could not be decoded: \(message)"
        case .scanImplementationInvalid(let codes):
            return "The retained scan implementation is invalid: \(codes.joined(separator: ", "))."
        case .transformedDesignMismatch:
            return "The imported transformed design and scan implementation do not match."
        case .processMismatch:
            return "The imported scan evidence and ATPG PDK identify different processes."
        case .gateLevelFaultSourceRequired:
            return "Realized-scan ATPG requires the gate-level fault source."
        case .clockIDsInvalid:
            return "Realized-scan ATPG clock IDs must be non-empty and unique."
        case .domainClockMappingMismatch:
            return "The domain-to-clock mapping must exactly cover the realized scan domains."
        case .unknownClockID(let domainID, let clockID):
            return "Scan domain \(domainID) refers to unknown clock \(clockID)."
        }
    }
}
