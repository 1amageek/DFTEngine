import Foundation

public enum DFTOracleCorrelationError: Error, LocalizedError, Sendable, Hashable {
    case invalidCorpus(String)
    case duplicateObservation(String)
    case unknownObservation(String)
    case invalidObservation(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCorpus(let message):
            return "DFT oracle corpus is invalid: \(message)"
        case .duplicateObservation(let caseID):
            return "DFT oracle correlation received duplicate observation \(caseID)."
        case .unknownObservation(let caseID):
            return "DFT oracle correlation received an observation for unknown case \(caseID)."
        case .invalidObservation(let message):
            return "DFT oracle observation is invalid: \(message)"
        }
    }
}
