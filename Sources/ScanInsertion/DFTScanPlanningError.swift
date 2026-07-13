import Foundation

public enum DFTScanPlanningError: Error, LocalizedError, Sendable, Hashable {
    case invalidDomain(String)
    case maximumChainLengthExceeded(domainID: String, actual: Int, maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidDomain(let message):
            return "Scan architecture is invalid: \(message)."
        case .maximumChainLengthExceeded(let domainID, let actual, let maximum):
            return "Scan domain \(domainID) requires chain length \(actual), exceeding maximum \(maximum)."
        }
    }
}
