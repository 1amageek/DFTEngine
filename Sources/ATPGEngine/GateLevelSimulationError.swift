import Foundation
import DFTCore

public enum GateLevelSimulationError: Error, LocalizedError, Sendable, Hashable {
    case gateDesignMissing
    case primaryInputNetMissing(String)
    case primaryOutputNetMissing(String)
    case inputAssignmentMissing(String)
    case unsupportedCellType(instance: String, type: String)
    case sequentialCellUnsupported(instance: String, type: String)
    case outputPinContractInvalid(instance: String)
    case inputValueMissing(instance: String, pin: String)
    case outputValueMissing(instance: String, pin: String)
    case cyclicOrUndrivenLogic([String])
    case unsupportedFaultFamily(DFTFaultFamily)
    case faultValueMissing(String)
    case faultLocationMissing(String)
    case transitionDirectionMissing(String)
    case faultValueUnavailable(String)
    case sequentialControlContractMissing(instance: String, type: String)
    case sequentialElementContractMissing(instance: String, type: String)
    case sequentialElementKindMismatch(instance: String, type: String, expected: DFTSequentialElementKind)
    case sequentialControlPinMissing(instance: String, pin: String)
    case sequentialControlConflict(instance: String)

    public var errorDescription: String? {
        switch self {
        case .gateDesignMissing:
            return "Gate-level simulation requires a canonical gate design."
        case .primaryInputNetMissing(let name):
            return "Primary input port \(name) is not connected to a gate net with the same name or ID."
        case .primaryOutputNetMissing(let name):
            return "Primary output port \(name) is not connected to a gate net with the same name or ID."
        case .inputAssignmentMissing(let name):
            return "No binary assignment was provided for primary input \(name)."
        case .unsupportedCellType(let instance, let type):
            return "Combinational gate simulation does not support cell \(instance) of type \(type)."
        case .sequentialCellUnsupported(let instance, let type):
            return "Gate-level ATPG does not yet simulate sequential cell \(instance) of type \(type)."
        case .outputPinContractInvalid(let instance):
            return "Combinational cell \(instance) must have exactly one output pin."
        case .inputValueMissing(let instance, let pin):
            return "Input value for \(instance).\(pin) could not be resolved."
        case .outputValueMissing(let instance, let pin):
            return "Output pin \(instance).\(pin) is not connected to a net."
        case .cyclicOrUndrivenLogic(let instances):
            return "Gate-level simulation could not resolve cell inputs for: \(instances.joined(separator: ", "))."
        case .unsupportedFaultFamily(let family):
            return "Gate-level simulation only supports stuck-at faults, not \(family.rawValue)."
        case .faultValueMissing(let faultID):
            return "Stuck-at fault \(faultID) does not declare a stuck-at value."
        case .faultLocationMissing(let faultID):
            return "Stuck-at fault \(faultID) does not identify a gate net."
        case .transitionDirectionMissing(let faultID):
            return "Transition fault \(faultID) must declare slow-to-rise or slow-to-fall direction."
        case .faultValueUnavailable(let faultID):
            return "Transition fault \(faultID) could not resolve the target net value."
        case .sequentialControlContractMissing(let instance, let type):
            return "Sequential cell \(instance) of type \(type) has reset/set controls but no explicit cell contract."
        case .sequentialElementContractMissing(let instance, let type):
            return "Sequential cell \(instance) of type \(type) requires an explicit element contract."
        case .sequentialElementKindMismatch(let instance, let type, let expected):
            return "Sequential cell \(instance) of type \(type) requires a \(expected.rawValue) element contract."
        case .sequentialControlPinMissing(let instance, let pin):
            return "Sequential cell \(instance) does not provide the contract pin \(pin)."
        case .sequentialControlConflict(let instance):
            return "Sequential cell \(instance) asserted reset and set at the same time."
        }
    }
}
