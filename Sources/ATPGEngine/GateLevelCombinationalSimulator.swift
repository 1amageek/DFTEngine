import DFTCore
import LogicIR

public protocol GateLevelSimulating: Sendable {
    func simulate(
        snapshot: LogicDesignSnapshot,
        inputs: [String: Bool],
        fault: DFTFault?
    ) throws -> GateLevelSimulationResult
}

public struct GateLevelCombinationalSimulator: GateLevelSimulating {
    public init() {}

    public func simulate(
        snapshot: LogicDesignSnapshot,
        inputs: [String: Bool],
        fault: DFTFault? = nil
    ) throws -> GateLevelSimulationResult {
        guard let gate = snapshot.gate else {
            throw GateLevelSimulationError.gateDesignMissing
        }
        guard let module = gate.modules.first(where: { $0.name == gate.topModuleName }) else {
            throw GateLevelSimulationError.gateDesignMissing
        }
        let netsByID = Dictionary(uniqueKeysWithValues: module.nets.map { ($0.id, $0) })
        if let fault {
            guard fault.family == .stuckAt else {
                throw GateLevelSimulationError.unsupportedFaultFamily(fault.family)
            }
            guard fault.stuckAtValue != nil else {
                throw GateLevelSimulationError.faultValueMissing(fault.id)
            }
            guard !fault.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GateLevelSimulationError.faultLocationMissing(fault.id)
            }
            guard module.nets.contains(where: { net in
                fault.location == net.id || fault.location == net.name
                    || fault.location.hasSuffix(".\(net.id)")
                    || fault.location.hasSuffix(".\(net.name)")
            }) else {
                throw GateLevelSimulationError.faultLocationMissing(fault.id)
            }
        }
        var values: [String: Bool] = [:]

        for port in module.ports where port.direction == .input {
            guard let net = net(for: port.name, in: module.nets) else {
                throw GateLevelSimulationError.primaryInputNetMissing(port.name)
            }
            guard let value = inputs[port.name] else {
                throw GateLevelSimulationError.inputAssignmentMissing(port.name)
            }
            values[net.id] = forcedValue(for: net, fault: fault) ?? value
        }

        var pending = module.cells
        while !pending.isEmpty {
            var progressed = false
            var remaining: [GateCell] = []
            for cell in pending {
                let kind = try primitiveKind(for: cell)
                let inputPins = cell.pins.filter { $0.direction == .input }
                guard inputPins.allSatisfy({ pin in
                    guard let netID = pin.netID else { return false }
                    return values[netID] != nil
                }) else {
                    remaining.append(cell)
                    continue
                }
                let inputValues = try inputPins.map { pin -> Bool in
                    guard let netID = pin.netID, let value = values[netID] else {
                        throw GateLevelSimulationError.inputValueMissing(
                            instance: cell.instanceName,
                            pin: pin.name
                        )
                    }
                    return value
                }
                let outputPins = cell.pins.filter { $0.direction == .output }
                guard outputPins.count == 1, let outputPin = outputPins.first else {
                    throw GateLevelSimulationError.outputPinContractInvalid(instance: cell.instanceName)
                }
                guard let outputNetID = outputPin.netID, let outputNet = netsByID[outputNetID] else {
                    throw GateLevelSimulationError.outputValueMissing(
                        instance: cell.instanceName,
                        pin: outputPin.name
                    )
                }
                let outputValue = try evaluate(kind: kind, inputs: inputValues)
                values[outputNetID] = forcedValue(for: outputNet, fault: fault) ?? outputValue
                progressed = true
            }
            guard progressed else {
                throw GateLevelSimulationError.cyclicOrUndrivenLogic(
                    remaining.map(\.instanceName).sorted()
                )
            }
            pending = remaining
        }

        var observed: [String: Bool] = [:]
        for port in module.ports where port.direction == .output {
            guard let net = net(for: port.name, in: module.nets) else {
                throw GateLevelSimulationError.primaryOutputNetMissing(port.name)
            }
            guard let value = values[net.id] else {
                throw GateLevelSimulationError.primaryOutputNetMissing(port.name)
            }
            observed[port.name] = value
        }
        guard !observed.isEmpty else {
            throw GateLevelSimulationError.primaryOutputNetMissing("<none>")
        }
        return GateLevelSimulationResult(observedValues: observed)
    }

    private func net(for portName: String, in nets: [GateNet]) -> GateNet? {
        nets.first { $0.name == portName || $0.id == portName }
    }

    private func forcedValue(for net: GateNet, fault: DFTFault?) -> Bool? {
        guard let fault else { return nil }
        guard fault.family == .stuckAt else { return nil }
        guard let value = fault.stuckAtValue else { return nil }
        let location = fault.location
        let matches = location == net.id || location == net.name
            || location.hasSuffix(".\(net.id)")
            || location.hasSuffix(".\(net.name)")
        guard matches else { return nil }
        return value == .one
    }

    private func primitiveKind(for cell: GateCell) throws -> PrimitiveKind {
        let normalized = cell.type
            .uppercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        if normalized.hasPrefix("DFF") || normalized.hasPrefix("SDFF")
            || normalized.hasPrefix("LATCH") || normalized.hasPrefix("SCAN") {
            throw GateLevelSimulationError.sequentialCellUnsupported(
                instance: cell.instanceName,
                type: cell.type
            )
        }
        if normalized.hasPrefix("NAND") { return .nand }
        if normalized.hasPrefix("NOR") { return .nor }
        if normalized.hasPrefix("XNOR") { return .xnor }
        if normalized.hasPrefix("XOR") { return .xor }
        if normalized.hasPrefix("AND") { return .and }
        if normalized.hasPrefix("OR") { return .or }
        if normalized.hasPrefix("INV") || normalized.hasPrefix("NOT") { return .not }
        if normalized.hasPrefix("BUF") { return .buffer }
        throw GateLevelSimulationError.unsupportedCellType(
            instance: cell.instanceName,
            type: cell.type
        )
    }

    private func evaluate(kind: PrimitiveKind, inputs: [Bool]) throws -> Bool {
        guard !inputs.isEmpty else {
            throw GateLevelSimulationError.inputValueMissing(instance: "<gate>", pin: "<none>")
        }
        switch kind {
        case .and:
            return inputs.allSatisfy { $0 }
        case .nand:
            return !inputs.allSatisfy { $0 }
        case .or:
            return inputs.contains { $0 }
        case .nor:
            return !inputs.contains { $0 }
        case .xor:
            return inputs.filter { $0 }.count.isMultiple(of: 2) == false
        case .xnor:
            return inputs.filter { $0 }.count.isMultiple(of: 2)
        case .not:
            return !inputs[0]
        case .buffer:
            return inputs[0]
        }
    }
}

private enum PrimitiveKind {
    case and
    case nand
    case or
    case nor
    case xor
    case xnor
    case not
    case buffer
}
