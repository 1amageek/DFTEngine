import DFTCore
import Foundation

public enum DFTGateLevelMemoryBISTTransformError: Error, LocalizedError, Sendable, Hashable {
    case gateDesignMissing
    case topModuleMissing(String)
    case mappingInvalid(String)
    case targetSetMismatch
    case duplicateBinding(String)
    case macroMissing(String)
    case macroTypeMismatch(instance: String, expected: String, actual: String)
    case unsupportedMacroType(String)
    case unsupportedAlgorithm(String)
    case pinMissing(instance: String, pin: String)
    case pinDirectionInvalid(instance: String, pin: String)
    case pinNetMissing(instance: String, pin: String)
    case clockDomainMismatch
    case generatedNameCollision(String)
    case controlSignalConflict(String)
    case transformedDesignInvalid(String)

    public var errorDescription: String? {
        switch self {
        case .gateDesignMissing:
            "Canonical memory-BIST transformation requires a gate-level design."
        case .topModuleMissing(let name):
            "Gate design does not contain top module \(name)."
        case .mappingInvalid(let reason):
            "Memory-BIST helper-cell mapping is invalid: \(reason)."
        case .targetSetMismatch:
            "Memory-BIST target instances do not exactly match the macro bindings."
        case .duplicateBinding(let name):
            "Memory macro \(name) is bound more than once."
        case .macroMissing(let name):
            "Memory macro \(name) does not exist in the top gate module."
        case .macroTypeMismatch(let instance, let expected, let actual):
            "Memory macro \(instance) has type \(actual); binding requires \(expected)."
        case .unsupportedMacroType(let type):
            "Memory-BIST cell mapping does not qualify macro type \(type)."
        case .unsupportedAlgorithm(let id):
            "Memory-BIST cell mapping does not qualify algorithm \(id)."
        case .pinMissing(let instance, let pin):
            "Memory macro \(instance) does not contain pin \(pin)."
        case .pinDirectionInvalid(let instance, let pin):
            "Memory macro pin \(instance).\(pin) has an incompatible direction."
        case .pinNetMissing(let instance, let pin):
            "Memory macro pin \(instance).\(pin) is not connected to a canonical net."
        case .clockDomainMismatch:
            "Native memory-BIST requires all bound macros to use one explicit clock net."
        case .generatedNameCollision(let name):
            "Memory-BIST generated name collides with \(name)."
        case .controlSignalConflict(let name):
            "Memory-BIST control signal \(name) conflicts with an existing port."
        case .transformedDesignInvalid(let message):
            "Transformed memory-BIST design is invalid: \(message)"
        }
    }
}
