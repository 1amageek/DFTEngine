import DFTCore
import Foundation

public enum DFTMemoryBISTExecutionError: Error, LocalizedError, Sendable, Hashable {
    case operationMismatch
    case configurationMissing
    case bindingsMissing
    case resultNotCompleted(DFTExecutionStatus)

    public var errorDescription: String? {
        switch self {
        case .operationMismatch:
            "The memory BIST engine requires a BIST request."
        case .configurationMissing:
            "The memory BIST engine requires a memory BIST configuration."
        case .bindingsMissing:
            "The memory BIST engine requires complete macro port bindings."
        case .resultNotCompleted(let status):
            "The memory BIST engine returned a non-completed execution status: \(status.rawValue)."
        }
    }
}
