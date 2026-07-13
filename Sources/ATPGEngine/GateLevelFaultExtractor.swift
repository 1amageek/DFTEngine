import DFTCore
import LogicIR

public struct GateLevelFaultExtractor: DFTFaultExtracting {
    public let implementationID: String

    public init(implementationID: String = "native-gate-level-stuck-at-extractor") {
        self.implementationID = implementationID
    }

    public func extract(
        from snapshot: LogicDesignSnapshot,
        reference: LogicDesignReference
    ) throws -> DFTFaultUniverse {
        guard let gate = snapshot.gate else {
            throw GateLevelFaultExtractorError.gateDesignMissing
        }
        let validation = LogicDesignValidator().validate(gate)
        guard validation.isValid else {
            let message = validation.diagnostics
                .filter { $0.severity == .error }
                .map { "\($0.code): \($0.message)" }
                .joined(separator: "; ")
            throw GateLevelFaultExtractorError.invalidGateDesign(message)
        }
        guard let module = gate.modules.first(where: { $0.name == gate.topModuleName }) else {
            throw GateLevelFaultExtractorError.topModuleMissing(gate.topModuleName)
        }

        let pinsByID = Dictionary(
            uniqueKeysWithValues: module.cells.flatMap { cell in
                cell.pins.map { ($0.id, $0) }
            }
        )
        let drivenNets = module.nets.filter { net in
            if !net.driverPinIDs.isEmpty {
                return true
            }
            return module.cells.contains { cell in
                cell.pins.contains { pin in
                    pin.netID == net.id
                        && (pin.direction == .output || pin.direction == .inOut)
                }
            }
        }.filter { net in
            net.driverPinIDs.allSatisfy { pinsByID[$0] != nil }
        }.sorted {
            $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
        }
        guard !drivenNets.isEmpty else {
            throw GateLevelFaultExtractorError.noDrivenNets(module.name)
        }

        let locationPrefix = "\(module.name)."
        let faults = drivenNets.flatMap { net in
            let location = locationPrefix + net.name
            return [
                DFTFault(
                    id: "\(location).sa0",
                    family: .stuckAt,
                    location: location,
                    stuckAtValue: .zero
                ),
                DFTFault(
                    id: "\(location).sa1",
                    family: .stuckAt,
                    location: location,
                    stuckAtValue: .one
                ),
            ]
        }
        return DFTFaultUniverse(
            name: "gate-level-stuck-at",
            revision: "\(implementationID):\(reference.designDigest)",
            faults: faults,
            declaredBy: implementationID
        )
    }
}
