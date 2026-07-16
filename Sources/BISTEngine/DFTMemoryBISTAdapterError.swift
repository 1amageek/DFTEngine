import Foundation
import DFTCore

public enum DFTMemoryBISTAdapterError: Error, LocalizedError, Sendable, Hashable {
    case operationMismatch
    case configurationMissing
    case bindingsMissing
    case resultNotCompleted(DFTExecutionStatus)
    case toolTrustRejected(String)

    public var errorDescription: String? {
        switch self {
        case .operationMismatch:
            return "The memory BIST adapter requires a BIST request."
        case .configurationMissing:
            return "The memory BIST adapter requires a memory BIST configuration."
        case .bindingsMissing:
            return "The memory BIST adapter requires complete macro port bindings."
        case .resultNotCompleted(let status):
            return "The memory BIST adapter returned a non-completed execution status: \(status.rawValue)."
        case .toolTrustRejected(let toolID):
            return "ToolQualification rejected memory BIST implementation \(toolID)."
        }
    }
}
