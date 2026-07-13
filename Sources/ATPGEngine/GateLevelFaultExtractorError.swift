import Foundation

public enum GateLevelFaultExtractorError: Error, LocalizedError, Sendable, Hashable {
    case gateDesignMissing
    case invalidGateDesign(String)
    case topModuleMissing(String)
    case noDrivenNets(String)

    public var errorDescription: String? {
        switch self {
        case .gateDesignMissing:
            return "Gate-level ATPG requires a canonical gate design in the LogicDesignSnapshot."
        case .invalidGateDesign(let message):
            return "Gate-level fault extraction requires valid gate connectivity: \(message)"
        case .topModuleMissing(let name):
            return "Gate-level fault extraction could not resolve top module \(name)."
        case .noDrivenNets(let name):
            return "Gate-level fault extraction found no driven nets in top module \(name)."
        }
    }
}
