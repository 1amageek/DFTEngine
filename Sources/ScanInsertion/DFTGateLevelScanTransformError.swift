import Foundation
import LogicIR

public enum DFTGateLevelScanTransformError: Error, LocalizedError, Sendable, Hashable {
    case topModuleMissing(String)
    case noSequentialCells
    case elementCountMismatch(expected: Int, actual: Int)
    case cellLibraryBindingMissing(instance: String, type: String)
    case scanCellMappingMismatch(functionalType: String, expected: String, actual: String)
    case cellPinContractMissing(instance: String, pin: String)
    case clockConnectivityUnresolved(instance: String, actual: String?, expected: [String])
    case resetConnectivityUnresolved(instance: String, actual: String?, expected: String)
    case domainElementCountMismatch(domainID: String, expected: Int, actual: Int)
    case sequentialCellUnsupported(instance: String, type: String)
    case outputPinMissing(instance: String)
    case controlPortConflict(name: String)
    case portNetMissing(String)
    case generatedNetConflict(name: String)
    case compressionConfigurationInvalid(String)
    case compressionCellConflict(String)
    case transformedDesignInvalid([LogicDiagnostic])

    public var errorDescription: String? {
        switch self {
        case .topModuleMissing(let name):
            return "Gate design does not contain the requested top module \(name)."
        case .noSequentialCells:
            return "Gate design contains no supported sequential cells for scan insertion."
        case .elementCountMismatch(let expected, let actual):
            return "Scan architecture declares \(expected) scan elements, but the gate design contains \(actual) sequential cells."
        case .cellLibraryBindingMissing(let instance, let type):
            return "Sequential cell \(instance) of type \(type) has no process-scoped cell-library binding."
        case .scanCellMappingMismatch(let functionalType, let expected, let actual):
            return "Cell-library binding for \(functionalType) requires scan cell \(expected), but policy requested \(actual)."
        case .cellPinContractMissing(let instance, let pin):
            return "Cell \(instance) is missing the library-mandated pin contract \(pin)."
        case .clockConnectivityUnresolved(let instance, let actual, let expected):
            let actualValue = actual ?? "<missing>"
            return "Sequential cell \(instance) is connected to clock \(actualValue); expected one of \(expected.joined(separator: ", ")) from the scan architecture."
        case .resetConnectivityUnresolved(let instance, let actual, let expected):
            let actualValue = actual ?? "<missing>"
            return "Sequential cell \(instance) is connected to reset \(actualValue); expected \(expected) for its scan domain."
        case .domainElementCountMismatch(let domainID, let expected, let actual):
            return "Scan domain \(domainID) declares \(expected) sequential elements, but \(actual) were bound by clock/reset connectivity."
        case .sequentialCellUnsupported(let instance, let type):
            return "Sequential cell \(instance) of type \(type) cannot be transformed with the current scan-cell contract."
        case .outputPinMissing(let instance):
            return "Sequential cell \(instance) has no recognizable state output pin."
        case .controlPortConflict(let name):
            return "DFT control port \(name) already exists with an incompatible direction."
        case .portNetMissing(let name):
            return "Gate module port \(name) has no canonical net binding."
        case .generatedNetConflict(let name):
            return "DFT generated net \(name) collides with an incompatible existing net."
        case .compressionConfigurationInvalid(let message):
            return "Scan compression configuration is invalid: \(message)"
        case .compressionCellConflict(let name):
            return "Scan compression helper cell \(name) collides with an existing cell."
        case .transformedDesignInvalid(let diagnostics):
            let messages = diagnostics.map(\.message).joined(separator: "; ")
            return "Transformed gate design failed validation: \(messages)"
        }
    }
}
