import DFTCore
import LogicIR

public struct GateLevelSequentialSimulator: GateLevelSequentialSimulating {
    public init() {}

    public func simulate(
        snapshot: LogicDesignSnapshot,
        inputCycles: [[String: Bool]],
        initialState: [String: Bool] = [:],
        fault: DFTFault? = nil
    ) throws -> GateLevelSequentialSimulationResult {
        try simulate(
            snapshot: snapshot,
            inputCycles: inputCycles,
            initialState: initialState,
            fault: fault,
            sequentialContracts: []
        )
    }

    public func simulate(
        snapshot: LogicDesignSnapshot,
        inputCycles: [[String: Bool]],
        initialState: [String: Bool] = [:],
        fault: DFTFault? = nil,
        sequentialContracts: [DFTSequentialCellContract] = [],
        transitionFault: DFTFault? = nil,
        transitionHoldValue: Bool? = nil
    ) throws -> GateLevelSequentialSimulationResult {
        guard !inputCycles.isEmpty else {
            throw GateLevelSimulationError.inputAssignmentMissing("<cycle>")
        }
        guard let gate = snapshot.gate,
              let module = gate.modules.first(where: { $0.name == gate.topModuleName }) else {
            throw GateLevelSimulationError.gateDesignMissing
        }
        let sequentialCells = module.cells.filter {
            isSupportedSequentialCell($0, contracts: sequentialContracts)
        }
        guard !sequentialCells.isEmpty else {
            throw GateLevelSimulationError.sequentialCellUnsupported(
                instance: "<none>",
                type: "no supported DFF"
            )
        }
        let unsupportedSequentialCells = module.cells.filter {
            isSequential($0) && !isSupportedSequentialCell($0, contracts: sequentialContracts)
        }
        if let unsupported = unsupportedSequentialCells.first {
            throw GateLevelSimulationError.sequentialCellUnsupported(
                instance: unsupported.instanceName,
                type: unsupported.type
            )
        }
        let netsByID = Dictionary(uniqueKeysWithValues: module.nets.map { ($0.id, $0) })
        let sequentialState = try sequentialCells.map {
            try makeStateBinding(
                cell: $0,
                netsByID: netsByID,
                contracts: sequentialContracts
            )
        }

        var state = Dictionary(uniqueKeysWithValues: sequentialState.map { binding in
            (binding.outputNetID, initialState[binding.outputNetID] ?? false)
        })
        var previousClocks = Dictionary(uniqueKeysWithValues: sequentialState.map { ($0.clockNetID, false) })
        var observations: [[String: Bool]] = []
        var netObservations: [[String: Bool]] = []

        for (cycleIndex, cycleInputs) in inputCycles.enumerated() {
            let transitionActive = transitionFault != nil
                && transitionHoldValue != nil
                && cycleIndex == inputCycles.count - 1
            var values: [String: Bool] = [:]
            for port in module.ports where port.direction == .input {
                guard let net = net(for: port, in: module) else {
                    throw GateLevelSimulationError.primaryInputNetMissing(port.name)
                }
                guard let value = cycleInputs[port.name] else {
                    throw GateLevelSimulationError.inputAssignmentMissing(port.name)
                }
                values[net.id] = forcedValue(
                    for: net,
                    fault: fault,
                    transitionFault: transitionFault,
                    transitionHoldValue: transitionHoldValue,
                    transitionActive: transitionActive
                ) ?? value
            }
            for binding in sequentialState {
                let (outputNet, stateValue) = try resolvedOutputState(
                    for: binding,
                    netsByID: netsByID,
                    state: state
                )
                values[binding.outputNetID] = forcedValue(
                    for: outputNet,
                    fault: fault,
                    transitionFault: transitionFault,
                    transitionHoldValue: transitionHoldValue,
                    transitionActive: transitionActive
                ) ?? stateValue
            }

            try evaluateCombinationalCells(
                module: module,
                values: &values,
                netsByID: netsByID,
                fault: fault,
                transitionFault: transitionFault,
                transitionHoldValue: transitionHoldValue,
                transitionActive: transitionActive
            )

            var nextState = state
            var asynchronousControlChanged = false
            for binding in sequentialState {
                let resetActive = try controlIsActive(
                    netIDs: binding.resetNetIDs,
                    polarity: binding.resetPolarity,
                    values: values,
                    instanceName: binding.instanceName
                )
                let setActive = try controlIsActive(
                    netIDs: binding.setNetIDs,
                    polarity: binding.setPolarity,
                    values: values,
                    instanceName: binding.instanceName
                )
                guard !(resetActive && setActive) else {
                    throw GateLevelSimulationError.sequentialControlConflict(
                        instance: binding.instanceName
                    )
                }
                guard binding.controlTiming == .asynchronous else {
                    continue
                }
                let stateBeforeControl = nextState[binding.outputNetID]
                if resetActive {
                    nextState[binding.outputNetID] = false
                } else if setActive {
                    nextState[binding.outputNetID] = true
                }
                if stateBeforeControl != nextState[binding.outputNetID] {
                    asynchronousControlChanged = true
                    let (outputNet, stateValue) = try resolvedOutputState(
                        for: binding,
                        netsByID: netsByID,
                        state: nextState
                    )
                    values[binding.outputNetID] = forcedValue(
                        for: outputNet,
                        fault: fault,
                        transitionFault: transitionFault,
                        transitionHoldValue: transitionHoldValue,
                        transitionActive: transitionActive
                    ) ?? stateValue
                }
            }
            if asynchronousControlChanged {
                try evaluateCombinationalCells(
                    module: module,
                    values: &values,
                    netsByID: netsByID,
                    fault: fault,
                    transitionFault: transitionFault,
                    transitionHoldValue: transitionHoldValue,
                    transitionActive: transitionActive
                )
            }
            netObservations.append(values)
            observations.append(try observedOutputs(module: module, values: values))

            for binding in sequentialState {
                guard let clockValue = values[binding.clockNetID],
                      let previousClock = previousClocks[binding.clockNetID] else {
                    throw GateLevelSimulationError.inputValueMissing(
                        instance: binding.instanceName,
                        pin: "CLK"
                    )
                }
                let captureActive: Bool
                switch binding.elementKind {
                case .edgeTriggered:
                    captureActive = isActiveEdge(
                        previous: previousClock,
                        current: clockValue,
                        edge: binding.clockEdge
                    )
                case .levelSensitive:
                    captureActive = controlIsActive(
                        value: clockValue,
                        polarity: binding.latchEnablePolarity
                    )
                }
                if captureActive {
                    let resetActive = try controlIsActive(
                        netIDs: binding.resetNetIDs,
                        polarity: binding.resetPolarity,
                        values: values,
                        instanceName: binding.instanceName
                    )
                    let setActive = try controlIsActive(
                        netIDs: binding.setNetIDs,
                        polarity: binding.setPolarity,
                        values: values,
                        instanceName: binding.instanceName
                    )
                    guard !(resetActive && setActive) else {
                        throw GateLevelSimulationError.sequentialControlConflict(
                            instance: binding.instanceName
                        )
                    }
                    if resetActive {
                        nextState[binding.outputNetID] = false
                        continue
                    }
                    if setActive {
                        nextState[binding.outputNetID] = true
                        continue
                    }
                    let nextNetID: String
                    if let scanEnableNetID = binding.scanEnableNetID,
                       values[scanEnableNetID] == true,
                       let scanInNetID = binding.scanInNetID {
                        nextNetID = scanInNetID
                    } else {
                        nextNetID = binding.dataNetID
                    }
                    guard let nextValue = values[nextNetID] else {
                        throw GateLevelSimulationError.inputValueMissing(
                            instance: binding.instanceName,
                            pin: nextNetID == binding.dataNetID ? "D" : "SI"
                        )
                    }
                    guard let outputNet = netsByID[binding.outputNetID] else {
                        throw GateLevelSimulationError.outputValueMissing(
                            instance: binding.instanceName,
                            pin: "Q"
                        )
                    }
                    nextState[binding.outputNetID] = forcedValue(
                        for: outputNet,
                        fault: fault,
                        transitionFault: transitionFault,
                        transitionHoldValue: transitionHoldValue,
                        transitionActive: transitionActive
                    ) ?? nextValue
                }
            }
            for clockNetID in previousClocks.keys {
                guard let clockValue = values[clockNetID] else {
                    throw GateLevelSimulationError.inputValueMissing(
                        instance: "<clock>",
                        pin: clockNetID
                    )
                }
                previousClocks[clockNetID] = clockValue
            }
            state = nextState
        }

        return GateLevelSequentialSimulationResult(
            observedValues: observations,
            finalState: state,
            netValues: netObservations
        )
    }

    private func resolvedOutputState(
        for binding: SequentialStateBinding,
        netsByID: [String: GateNet],
        state: [String: Bool]
    ) throws -> (net: GateNet, value: Bool) {
        guard let outputNet = netsByID[binding.outputNetID] else {
            throw GateLevelSimulationError.outputValueMissing(
                instance: binding.instanceName,
                pin: "Q"
            )
        }
        guard let stateValue = state[binding.outputNetID] else {
            throw GateLevelSimulationError.inputValueMissing(
                instance: binding.instanceName,
                pin: "Q"
            )
        }
        return (outputNet, stateValue)
    }

    private func makeStateBinding(
        cell: GateCell,
        netsByID: [String: GateNet],
        contracts: [DFTSequentialCellContract]
    ) throws -> SequentialStateBinding {
        let contract = contracts.first { $0.matches(cellType: cell.type) }
        let isLatch = normalizedType(cell.type).hasPrefix("LATCH")
        if isLatch, contract == nil {
            throw GateLevelSimulationError.sequentialElementContractMissing(
                instance: cell.instanceName,
                type: cell.type
            )
        }
        if isLatch, contract?.elementKind != .levelSensitive {
            throw GateLevelSimulationError.sequentialElementKindMismatch(
                instance: cell.instanceName,
                type: cell.type,
                expected: .levelSensitive
            )
        }
        if !isLatch, contract?.elementKind == .levelSensitive {
            throw GateLevelSimulationError.sequentialElementKindMismatch(
                instance: cell.instanceName,
                type: cell.type,
                expected: .edgeTriggered
            )
        }
        if contract == nil, !controlLikePins(in: cell).isEmpty {
            throw GateLevelSimulationError.sequentialControlContractMissing(
                instance: cell.instanceName,
                type: cell.type
            )
        }
        let dataPinName = contract?.dataPinName ?? "D"
        let outputPinName = contract?.outputPinName ?? "Q"
        let dataPin = pin(named: dataPinName, in: cell.pins)
        let outputPin = pin(named: outputPinName, in: cell.pins)
        let clockPin = contract?.clockPinNames
            .compactMap { pin(named: $0, in: cell.pins) }
            .first ?? clockPin(in: cell.pins)
        guard let dataNetID = dataPin?.netID,
              let outputNetID = outputPin?.netID,
              let clockNetID = clockPin?.netID,
              netsByID[dataNetID] != nil,
              netsByID[outputNetID] != nil,
              netsByID[clockNetID] != nil else {
            throw GateLevelSimulationError.sequentialCellUnsupported(
                instance: cell.instanceName,
                type: cell.type
            )
        }
        let scanInPin = contract?.scanInPinName
            .flatMap { pin(named: $0, in: cell.pins) }
            ?? scanInPin(in: cell.pins)
        let scanEnablePin = contract?.scanEnablePinName
            .flatMap { pin(named: $0, in: cell.pins) }
            ?? scanEnablePin(in: cell.pins)
        let scanInNetID = try scanNetID(
            pin: scanInPin,
            cell: cell,
            netsByID: netsByID,
            required: isScanCell(cell)
        )
        let scanEnableNetID = try scanNetID(
            pin: scanEnablePin,
            cell: cell,
            netsByID: netsByID,
            required: isScanCell(cell)
        )
        let resetPinNames = contract?.resetPinNames ?? []
        let setPinNames = contract?.setPinNames ?? []
        let resetNetIDs = try controlNetIDs(
            pinNames: resetPinNames,
            cell: cell,
            netsByID: netsByID
        )
        let setNetIDs = try controlNetIDs(
            pinNames: setPinNames,
            cell: cell,
            netsByID: netsByID
        )
        return SequentialStateBinding(
            instanceName: cell.instanceName,
            dataNetID: dataNetID,
            outputNetID: outputNetID,
            clockNetID: clockNetID,
            scanInNetID: scanInNetID,
            scanEnableNetID: scanEnableNetID,
            resetNetIDs: resetNetIDs,
            resetPolarity: contract?.resetPolarity ?? .activeHigh,
            setNetIDs: setNetIDs,
            setPolarity: contract?.setPolarity ?? .activeHigh,
            controlTiming: contract?.controlTiming ?? .asynchronous,
            clockEdge: contract?.clockEdge ?? .rising,
            elementKind: contract?.elementKind ?? .edgeTriggered,
            latchEnablePolarity: contract?.latchEnablePolarity ?? .activeHigh
        )
    }

    private func controlNetIDs(
        pinNames: [String],
        cell: GateCell,
        netsByID: [String: GateNet]
    ) throws -> [String] {
        try pinNames.map { pinName in
            guard let pin = pin(named: pinName, in: cell.pins),
                  let netID = pin.netID,
                  netsByID[netID] != nil else {
                throw GateLevelSimulationError.sequentialControlPinMissing(
                    instance: cell.instanceName,
                    pin: pinName
                )
            }
            return netID
        }
    }

    private func controlLikePins(in cell: GateCell) -> [GatePin] {
        let names = Set([
            "R", "RN", "RESET", "RESETN", "RST", "RSTN", "CLR", "CLRN", "CLEAR",
            "S", "SN", "SET", "SETN", "PRE", "PREN", "PRESET", "PRESETN"
        ])
        return cell.pins.filter {
            $0.direction == .input && names.contains(normalizedPinName($0.name))
        }
    }

    private func controlIsActive(
        netIDs: [String],
        polarity: DFTControlPolarity,
        values: [String: Bool],
        instanceName: String
    ) throws -> Bool {
        for netID in netIDs {
            guard let value = values[netID] else {
                throw GateLevelSimulationError.inputValueMissing(
                    instance: instanceName,
                    pin: netID
                )
            }
            let active = polarity == .activeHigh ? value : !value
            if active {
                return true
            }
        }
        return false
    }

    private func controlIsActive(
        value: Bool,
        polarity: DFTControlPolarity
    ) -> Bool {
        polarity == .activeHigh ? value : !value
    }

    private func isActiveEdge(
        previous: Bool,
        current: Bool,
        edge: DFTClockEdge
    ) -> Bool {
        switch edge {
        case .rising:
            return !previous && current
        case .falling:
            return previous && !current
        }
    }

    private func evaluateCombinationalCells(
        module: GateModule,
        values: inout [String: Bool],
        netsByID: [String: GateNet],
        fault: DFTFault?,
        transitionFault: DFTFault?,
        transitionHoldValue: Bool?,
        transitionActive: Bool
    ) throws {
        var pending = module.cells.filter { !isSequential($0) }
        while !pending.isEmpty {
            var progressed = false
            var remaining: [GateCell] = []
            for cell in pending {
                guard cell.pins.filter({ $0.direction == .input }).allSatisfy({
                    guard let netID = $0.netID else { return false }
                    return values[netID] != nil
                }) else {
                    remaining.append(cell)
                    continue
                }
                let inputValues = try cell.pins
                    .filter { $0.direction == .input }
                    .map { pin -> Bool in
                        guard let netID = pin.netID, let value = values[netID] else {
                            throw GateLevelSimulationError.inputValueMissing(
                                instance: cell.instanceName,
                                pin: pin.name
                            )
                        }
                        return value
                    }
                let outputs = cell.pins.filter { $0.direction == .output }
                guard outputs.count == 1, let output = outputs.first,
                      let outputNetID = output.netID,
                      let outputNet = netsByID[outputNetID] else {
                    throw GateLevelSimulationError.outputPinContractInvalid(instance: cell.instanceName)
                }
                let outputValue = try evaluate(cell: cell, inputs: inputValues)
                values[outputNetID] = forcedValue(
                    for: outputNet,
                    fault: fault,
                    transitionFault: transitionFault,
                    transitionHoldValue: transitionHoldValue,
                    transitionActive: transitionActive
                ) ?? outputValue
                progressed = true
            }
            guard progressed else {
                throw GateLevelSimulationError.cyclicOrUndrivenLogic(
                    remaining.map(\.instanceName).sorted()
                )
            }
            pending = remaining
        }
    }

    private func observedOutputs(
        module: GateModule,
        values: [String: Bool]
    ) throws -> [String: Bool] {
        var result: [String: Bool] = [:]
        for port in module.ports where port.direction == .output {
            guard let net = net(for: port, in: module),
                  let value = values[net.id] else {
                throw GateLevelSimulationError.primaryOutputNetMissing(port.name)
            }
            result[port.name] = value
        }
        guard !result.isEmpty else {
            throw GateLevelSimulationError.primaryOutputNetMissing("<none>")
        }
        return result
    }

    private func evaluate(cell: GateCell, inputs: [Bool]) throws -> Bool {
        guard !inputs.isEmpty else {
            throw GateLevelSimulationError.inputValueMissing(instance: cell.instanceName, pin: "<none>")
        }
        let normalized = normalizedType(cell.type)
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

    private func forcedValue(
        for net: GateNet,
        fault: DFTFault?,
        transitionFault: DFTFault?,
        transitionHoldValue: Bool?,
        transitionActive: Bool
    ) -> Bool? {
        if let fault,
           fault.family == .stuckAt,
           let stuckAtValue = fault.stuckAtValue,
           matches(fault.location, net: net) {
            return stuckAtValue == .one
        }
        if transitionActive,
           let transitionFault,
           transitionFault.family == .transition,
           let transitionHoldValue,
           matches(transitionFault.location, net: net) {
            return transitionHoldValue
        }
        return nil
    }

    private func matches(_ location: String, net: GateNet) -> Bool {
        location == net.id || location == net.name
            || location.hasSuffix(".\(net.id)")
            || location.hasSuffix(".\(net.name)")
    }

    private func net(for port: RTLPort, in module: GateModule) -> GateNet? {
        if let binding = module.portBindings?.first(where: { $0.portID == port.id }) {
            return module.nets.first { $0.id == binding.netID }
        }
        return module.nets.first { $0.name == port.name || $0.id == port.name }
    }

    private func pin(named name: String, in pins: [GatePin]) -> GatePin? {
        pins.first { $0.name.uppercased() == name.uppercased() }
    }

    private func normalizedPinName(_ name: String) -> String {
        name.uppercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private func clockPin(in pins: [GatePin]) -> GatePin? {
        pins.first { ["CLK", "CK", "CLOCK"].contains($0.name.uppercased()) }
    }

    private func scanInPin(in pins: [GatePin]) -> GatePin? {
        pins.first { ["SI", "SCANIN", "SDI"].contains($0.name.uppercased()) }
    }

    private func scanEnablePin(in pins: [GatePin]) -> GatePin? {
        pins.first { ["SE", "SCANEN", "SCANENABLE"].contains($0.name.uppercased()) }
    }

    private func scanNetID(
        pin: GatePin?,
        cell: GateCell,
        netsByID: [String: GateNet],
        required: Bool
    ) throws -> String? {
        guard let pin else {
            guard !required else {
                throw GateLevelSimulationError.sequentialCellUnsupported(
                    instance: cell.instanceName,
                    type: cell.type
                )
            }
            return nil
        }
        guard let netID = pin.netID, netsByID[netID] != nil else {
            throw GateLevelSimulationError.sequentialCellUnsupported(
                instance: cell.instanceName,
                type: cell.type
            )
        }
        return netID
    }

    private func isScanCell(_ cell: GateCell) -> Bool {
        let normalized = normalizedType(cell.type)
        return normalized.hasPrefix("SDFF") || normalized.hasPrefix("SCAN")
    }

    private func isSupportedDFF(
        _ cell: GateCell,
        contracts: [DFTSequentialCellContract]
    ) -> Bool {
        let normalized = normalizedType(cell.type)
        if normalized.hasPrefix("SDFF") {
            return !normalized.hasPrefix("SDFFR")
                && !normalized.hasPrefix("SDFFS")
                || contracts.contains { $0.matches(cellType: cell.type) }
        }
        return normalized.hasPrefix("DFF")
            && (!normalized.hasPrefix("DFFR") && !normalized.hasPrefix("DFFS")
                || contracts.contains { $0.matches(cellType: cell.type) })
    }

    private func isSupportedSequentialCell(
        _ cell: GateCell,
        contracts: [DFTSequentialCellContract]
    ) -> Bool {
        let normalized = normalizedType(cell.type)
        if normalized.hasPrefix("LATCH") {
            return true
        }
        return isSupportedDFF(cell, contracts: contracts)
    }

    private func isSequential(_ cell: GateCell) -> Bool {
        let normalized = normalizedType(cell.type)
        return normalized.hasPrefix("DFF")
            || normalized.hasPrefix("SDFF")
            || normalized.hasPrefix("SCAN")
            || normalized.hasPrefix("LATCH")
    }

    private func normalizedType(_ type: String) -> String {
        type.uppercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}

private struct SequentialStateBinding: Sendable, Hashable {
    var instanceName: String
    var dataNetID: String
    var outputNetID: String
    var clockNetID: String
    var scanInNetID: String?
    var scanEnableNetID: String?
    var resetNetIDs: [String]
    var resetPolarity: DFTControlPolarity
    var setNetIDs: [String]
    var setPolarity: DFTControlPolarity
    var controlTiming: DFTSequentialControlTiming
    var clockEdge: DFTClockEdge
    var elementKind: DFTSequentialElementKind
    var latchEnablePolarity: DFTControlPolarity
}
