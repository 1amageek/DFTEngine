import Foundation
import DFTCore

public enum DFTGateLevelBISTTransformError: Error, LocalizedError, Sendable, Hashable {
    case unsupportedKind(DFTBISTKind)
    case gateDesignMissing
    case topModuleMissing(String)
    case clockNetMissing(String)
    case controlSignalConflict(String)
    case targetBindingsMissing
    case cellMappingMissing
    case cellMappingInvalid(String)
    case targetSetMismatch
    case duplicateTargetBinding(String)
    case targetInstanceMissing(String)
    case pinMissing(instance: String, pin: String)
    case pinDirectionInvalid(instance: String, pin: String)
    case pinNetMissing(instance: String, pin: String)
    case netMissing(String)
    case generatedNameCollision(String)
    case targetPinSetEmpty(String)
    case transformedDesignInvalid(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedKind(let kind):
            return "Native canonical BIST transformation does not support \(kind.rawValue) targets."
        case .gateDesignMissing:
            return "Canonical BIST transformation requires a gate-level LogicDesignSnapshot."
        case .topModuleMissing(let name):
            return "Gate design does not contain top module \(name)."
        case .clockNetMissing(let name):
            return "BIST clock signal \(name) is not connected to a canonical gate net."
        case .controlSignalConflict(let name):
            return "BIST control signal \(name) conflicts with an existing non-input port."
        case .targetBindingsMissing:
            return "Canonical logic BIST requires explicit target input/output pin bindings."
        case .cellMappingMissing:
            return "Canonical logic BIST requires a process-bound helper-cell mapping."
        case .cellMappingInvalid(let reason):
            return "Canonical logic BIST helper-cell mapping is invalid: \(reason)."
        case .targetSetMismatch:
            return "Logic BIST target instances do not exactly match the bound target instances."
        case .duplicateTargetBinding(let name):
            return "BIST target instance \(name) is bound more than once."
        case .targetInstanceMissing(let name):
            return "BIST target instance \(name) does not exist in the top gate module."
        case .pinMissing(let instance, let pin):
            return "BIST target \(instance) does not contain pin \(pin)."
        case .pinDirectionInvalid(let instance, let pin):
            return "BIST target pin \(instance).\(pin) has an incompatible direction."
        case .pinNetMissing(let instance, let pin):
            return "BIST target pin \(instance).\(pin) is not connected to a canonical net."
        case .netMissing(let name):
            return "BIST transformation could not resolve net \(name)."
        case .generatedNameCollision(let name):
            return "BIST transformation generated a name that collides with \(name)."
        case .targetPinSetEmpty(let instance):
            return "BIST target \(instance) must bind at least one pattern input and one response output."
        case .transformedDesignInvalid(let message):
            return "Transformed BIST gate design failed validation: \(message)"
        }
    }
}
