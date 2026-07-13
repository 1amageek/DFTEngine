import Foundation

public enum GateLevelATPGError: Error, LocalizedError, Sendable, Hashable {
    case gateDesignMissing
    case inputWidthExceedsLimit(count: Int, limit: Int)
    case patternLengthInsufficient(required: Int, actual: Int)
    case simulationFailed(faultID: String, message: String)
    case sequentialSemanticsUnavailable
    case sequentialCycleLimitInvalid

    public var errorDescription: String? {
        switch self {
        case .gateDesignMissing:
            return "Gate-level ATPG requires a canonical gate design."
        case .inputWidthExceedsLimit(let count, let limit):
            return "Exhaustive gate-level ATPG would require \(count) primary inputs; the configured limit is \(limit)."
        case .patternLengthInsufficient(let required, let actual):
            return "ATPG pattern length \(actual) cannot encode \(required) primary input assignments."
        case .simulationFailed(let faultID, let message):
            return "Gate-level simulation failed while evaluating fault \(faultID): \(message)"
        case .sequentialSemanticsUnavailable:
            return "Gate-level ATPG found sequential cells, but bounded sequential semantics were not enabled."
        case .sequentialCycleLimitInvalid:
            return "Bounded sequential ATPG requires a positive sequential cycle limit."
        }
    }
}
