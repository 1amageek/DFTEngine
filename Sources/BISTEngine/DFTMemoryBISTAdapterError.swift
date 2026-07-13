import Foundation
import DFTCore
import XcircuitePackage

public enum DFTMemoryBISTAdapterError: Error, LocalizedError, Sendable, Hashable {
    case operationMismatch
    case configurationMissing
    case bindingsMissing
    case resultNotCompleted(XcircuiteEngineExecutionStatus)
    case qualificationInsufficient(DFTQualificationStatus)

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
        case .qualificationInsufficient(let status):
            return "The memory BIST adapter returned qualification status \(status.rawValue); process-qualified evidence is required."
        }
    }
}
