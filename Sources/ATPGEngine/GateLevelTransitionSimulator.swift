import DFTCore
import LogicIR

public struct GateLevelTransitionSimulator: GateLevelTransitionSimulating {
    public let sequentialSimulator: any GateLevelSequentialSimulating

    public init(
        sequentialSimulator: any GateLevelSequentialSimulating = GateLevelSequentialSimulator()
    ) {
        self.sequentialSimulator = sequentialSimulator
    }

    public func simulate(
        snapshot: LogicDesignSnapshot,
        launchInputs: [String: Bool],
        captureInputs: [String: Bool],
        fault: DFTFault
    ) throws -> GateLevelTransitionSimulationResult {
        guard fault.family == .transition else {
            throw GateLevelSimulationError.unsupportedFaultFamily(fault.family)
        }
        guard let transitionDirection = fault.transitionDirection else {
            throw GateLevelSimulationError.transitionDirectionMissing(fault.id)
        }
        guard let gate = snapshot.gate,
              let module = gate.modules.first(where: { $0.name == gate.topModuleName }) else {
            throw GateLevelSimulationError.gateDesignMissing
        }
        if let sequential = module.cells.first(where: { isSequential($0) }) {
            throw GateLevelSimulationError.sequentialCellUnsupported(
                instance: sequential.instanceName,
                type: sequential.type
            )
        }
        let launchGood = try evaluate(
            module: module,
            inputs: launchInputs,
            forcedNetID: nil,
            forcedValue: nil
        )
        let captureGood = try evaluate(
            module: module,
            inputs: captureInputs,
            forcedNetID: nil,
            forcedValue: nil
        )
        let targetNet = try targetNet(for: fault.location, in: module.nets)
        let launchValue = try value(for: targetNet, in: launchGood.values, faultID: fault.id)
        let captureValue = try value(for: targetNet, in: captureGood.values, faultID: fault.id)
        let shouldHold = transitionShouldHold(
            direction: transitionDirection,
            launchValue: launchValue,
            captureValue: captureValue
        )
        let faultyCapture = shouldHold
            ? try evaluate(
                module: module,
                inputs: captureInputs,
                forcedNetID: targetNet.id,
                forcedValue: launchValue
            )
            : captureGood
        return GateLevelTransitionSimulationResult(
            launchObservedValues: launchGood.observedValues,
            captureObservedValues: faultyCapture.observedValues,
            goodCaptureObservedValues: captureGood.observedValues
        )
    }

    public func simulate(
        snapshot: LogicDesignSnapshot,
        launchInputs: [String: Bool],
        captureInputs: [String: Bool],
        fault: DFTFault,
        sequentialContracts: [DFTSequentialCellContract]
    ) throws -> GateLevelTransitionSimulationResult {
        guard fault.family == .transition else {
            throw GateLevelSimulationError.unsupportedFaultFamily(fault.family)
        }
        guard let transitionDirection = fault.transitionDirection else {
            throw GateLevelSimulationError.transitionDirectionMissing(fault.id)
        }
        guard let gate = snapshot.gate,
              let module = gate.modules.first(where: { $0.name == gate.topModuleName }) else {
            throw GateLevelSimulationError.gateDesignMissing
        }
        guard module.cells.contains(where: isSequential) else {
            return try simulate(
                snapshot: snapshot,
                launchInputs: launchInputs,
                captureInputs: captureInputs,
                fault: fault
            )
        }
        let good = try sequentialSimulator.simulate(
            snapshot: snapshot,
            inputCycles: [launchInputs, captureInputs],
            initialState: [:],
            fault: nil,
            sequentialContracts: sequentialContracts
        )
        guard good.netValues.count == 2 else {
            throw GateLevelSimulationError.faultValueUnavailable(fault.id)
        }
        guard let targetNet = module.nets.first(where: { matches(fault.location, net: $0) }),
              let launchValue = good.netValues[0][targetNet.id],
              let captureValue = good.netValues[1][targetNet.id] else {
            throw GateLevelSimulationError.faultLocationMissing(fault.location)
        }
        let shouldHold = transitionShouldHold(
            direction: transitionDirection,
            launchValue: launchValue,
            captureValue: captureValue
        )
        guard shouldHold else {
            return GateLevelTransitionSimulationResult(
                launchObservedValues: good.observedValues[0],
                captureObservedValues: good.observedValues[1],
                goodCaptureObservedValues: good.observedValues[1]
            )
        }
        let faulty = try sequentialSimulator.simulate(
            snapshot: snapshot,
            inputCycles: [launchInputs, captureInputs],
            initialState: [:],
            fault: nil,
            sequentialContracts: sequentialContracts,
            transitionFault: fault,
            transitionHoldValue: launchValue
        )
        return GateLevelTransitionSimulationResult(
            launchObservedValues: good.observedValues[0],
            captureObservedValues: faulty.observedValues[1],
            goodCaptureObservedValues: good.observedValues[1]
        )
    }

    private func evaluate(
        module: GateModule,
        inputs: [String: Bool],
        forcedNetID: String?,
        forcedValue: Bool?
    ) throws -> NetlistEvaluation {
        let netsByID = Dictionary(uniqueKeysWithValues: module.nets.map { ($0.id, $0) })
        var values: [String: Bool] = [:]
        for port in module.ports where port.direction == .input {
            guard let net = net(for: port, in: module) else {
                throw GateLevelSimulationError.primaryInputNetMissing(port.name)
            }
            guard let inputValue = inputs[port.name] else {
                throw GateLevelSimulationError.inputAssignmentMissing(port.name)
            }
            values[net.id] = net.id == forcedNetID ? forcedValue : inputValue
        }

        var pending = module.cells
        while !pending.isEmpty {
            var progressed = false
            var remaining: [GateCell] = []
            for cell in pending {
                let inputPins = cell.pins.filter { $0.direction == .input }
                guard inputPins.allSatisfy({
                    guard let netID = $0.netID else { return false }
                    return values[netID] != nil
                }) else {
                    remaining.append(cell)
                    continue
                }
                let inputValues = try inputPins.map { pin -> Bool in
                    guard let netID = pin.netID, let inputValue = values[netID] else {
                        throw GateLevelSimulationError.inputValueMissing(
                            instance: cell.instanceName,
                            pin: pin.name
                        )
                    }
                    return inputValue
                }
                let outputPins = cell.pins.filter { $0.direction == .output }
                guard outputPins.count == 1, let outputPin = outputPins.first,
                      let outputNetID = outputPin.netID,
                      netsByID[outputNetID] != nil else {
                    throw GateLevelSimulationError.outputPinContractInvalid(instance: cell.instanceName)
                }
                let outputValue = try evaluate(cell: cell, inputs: inputValues)
                values[outputNetID] = outputNetID == forcedNetID ? forcedValue : outputValue
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
            guard let outputNet = net(for: port, in: module),
                  let outputValue = values[outputNet.id] else {
                throw GateLevelSimulationError.primaryOutputNetMissing(port.name)
            }
            observed[port.name] = outputValue
        }
        guard !observed.isEmpty else {
            throw GateLevelSimulationError.primaryOutputNetMissing("<none>")
        }
        return NetlistEvaluation(values: values, observedValues: observed)
    }

    private func targetNet(for location: String, in nets: [GateNet]) throws -> GateNet {
        guard let net = nets.first(where: { matches(location, net: $0) }) else {
            throw GateLevelSimulationError.faultLocationMissing(location)
        }
        return net
    }

    private func value(for net: GateNet, in values: [String: Bool], faultID: String) throws -> Bool {
        guard let value = values[net.id] else {
            throw GateLevelSimulationError.faultValueUnavailable(faultID)
        }
        return value
    }

    private func transitionShouldHold(
        direction: DFTTransitionDirection,
        launchValue: Bool,
        captureValue: Bool
    ) -> Bool {
        switch direction {
        case .slowToRise:
            return !launchValue && captureValue
        case .slowToFall:
            return launchValue && !captureValue
        }
    }

    private func evaluate(cell: GateCell, inputs: [Bool]) throws -> Bool {
        guard !inputs.isEmpty else {
            throw GateLevelSimulationError.inputValueMissing(instance: cell.instanceName, pin: "<none>")
        }
        let normalized = cell.type
            .uppercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        switch normalized {
        case let value where value.hasPrefix("NAND"):
            return !inputs.allSatisfy { $0 }
        case let value where value.hasPrefix("NOR"):
            return !inputs.contains { $0 }
        case let value where value.hasPrefix("XNOR"):
            return inputs.filter { $0 }.count.isMultiple(of: 2)
        case let value where value.hasPrefix("XOR"):
            return !inputs.filter { $0 }.count.isMultiple(of: 2)
        case let value where value.hasPrefix("AND"):
            return inputs.allSatisfy { $0 }
        case let value where value.hasPrefix("OR"):
            return inputs.contains { $0 }
        case let value where value.hasPrefix("INV") || value.hasPrefix("NOT"):
            return !inputs[0]
        case let value where value.hasPrefix("BUF"):
            return inputs[0]
        default:
            throw GateLevelSimulationError.unsupportedCellType(
                instance: cell.instanceName,
                type: cell.type
            )
        }
    }

    private func net(for port: RTLPort, in module: GateModule) -> GateNet? {
        if let binding = module.portBindings.first(where: { $0.portID == port.id }) {
            return module.nets.first { $0.id == binding.netID }
        }
        return module.nets.first { $0.name == port.name || $0.id == port.name }
    }

    private func matches(_ location: String, net: GateNet) -> Bool {
        location == net.id || location == net.name
            || location.hasSuffix(".\(net.id)")
            || location.hasSuffix(".\(net.name)")
    }

    private func isSequential(_ cell: GateCell) -> Bool {
        let normalized = cell.type
            .uppercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        return normalized.hasPrefix("DFF")
            || normalized.hasPrefix("SDFF")
            || normalized.hasPrefix("SCAN")
            || normalized.hasPrefix("LATCH")
    }
}

private struct NetlistEvaluation: Sendable, Hashable {
    var values: [String: Bool]
    var observedValues: [String: Bool]
}
