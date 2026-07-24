import DFTCore
import LogicIR

public struct DFTGateLevelScanTransformer: Sendable {
    public init() {}

    public func transform(
        snapshot: LogicDesignSnapshot,
        architecture: DFTScanArchitecture,
        plan: DFTScanPlan,
        policy: DFTScanInsertionPolicy,
        cellLibrary: DFTCellLibraryManifest
    ) throws -> DFTGateLevelScanTransformResult {
        guard var gate = snapshot.gate else {
            throw DFTDesignLoaderError.gateDesignMissing
        }
        guard let topIndex = gate.modules.firstIndex(where: { $0.name == gate.topModuleName }) else {
            throw DFTGateLevelScanTransformError.topModuleMissing(gate.topModuleName)
        }

        var module = gate.modules[topIndex]
        try ensureExplicitPortBindings(module: &module)
        try DFTCellLibraryManifestCodec.validate(cellLibrary)
        let bindingsByFunctionalType = Dictionary(
            uniqueKeysWithValues: cellLibrary.bindings.map { ($0.functionalCellType, $0) }
        )
        let sequentialIndices = module.cells.indices.filter { index in
            bindingsByFunctionalType[module.cells[index].type] != nil
                || isSequential(module.cells[index].type)
        }
        guard !sequentialIndices.isEmpty else {
            throw DFTGateLevelScanTransformError.noSequentialCells
        }
        guard sequentialIndices.count == plan.totalEstimatedElementCount else {
            throw DFTGateLevelScanTransformError.elementCountMismatch(
                expected: plan.totalEstimatedElementCount,
                actual: sequentialIndices.count
            )
        }

        let netsByID = Dictionary(uniqueKeysWithValues: module.nets.map { ($0.id, $0) })
        let expectedClockSignals = architecture.clocks.map(\.signalName).sorted()
        var cellIndicesByDomain: [String: [Int]] = [:]
        for cellIndex in sequentialIndices {
            let cell = module.cells[cellIndex]
            guard let binding = bindingsByFunctionalType[cell.type] else {
                throw DFTGateLevelScanTransformError.cellLibraryBindingMissing(
                    instance: cell.instanceName,
                    type: cell.type
                )
            }
            guard binding.scanCellType == policy.scanCellName else {
                throw DFTGateLevelScanTransformError.scanCellMappingMismatch(
                    functionalType: binding.functionalCellType,
                    expected: binding.scanCellType,
                    actual: policy.scanCellName
                )
            }
            guard cell.pins.contains(where: {
                $0.name.caseInsensitiveCompare(binding.dataPinName) == .orderedSame
            }) else {
                throw DFTGateLevelScanTransformError.cellPinContractMissing(
                    instance: cell.instanceName,
                    pin: binding.dataPinName
                )
            }
            if policy.requireTestMode && binding.testModePinName == nil {
                throw DFTGateLevelScanTransformError.cellPinContractMissing(
                    instance: cell.instanceName,
                    pin: "test-mode"
                )
            }
            let actualClock = signalName(
                for: cell,
                pinNames: binding.clockPinNames,
                netsByID: netsByID
            )
            guard let clock = architecture.clocks.first(where: { $0.signalName == actualClock }) else {
                throw DFTGateLevelScanTransformError.clockConnectivityUnresolved(
                    instance: cell.instanceName,
                    actual: actualClock,
                    expected: expectedClockSignals
                )
            }
            guard let domain = architecture.domains.first(where: { $0.clockID == clock.id }) else {
                throw DFTGateLevelScanTransformError.domainElementCountMismatch(
                    domainID: clock.id,
                    expected: 0,
                    actual: 1
                )
            }
            if let resetID = domain.resetID,
               let reset = architecture.resets.first(where: { $0.id == resetID }) {
                let actualReset = signalName(
                    for: cell,
                    pinNames: binding.resetPinNames,
                    netsByID: netsByID
                )
                guard actualReset == reset.signalName else {
                    throw DFTGateLevelScanTransformError.resetConnectivityUnresolved(
                        instance: cell.instanceName,
                        actual: actualReset,
                        expected: reset.signalName
                    )
                }
            }
            cellIndicesByDomain[domain.id, default: []].append(cellIndex)
        }
        for domain in architecture.domains {
            let actualCount = cellIndicesByDomain[domain.id]?.count ?? 0
            guard actualCount == domain.estimatedElementCount else {
                throw DFTGateLevelScanTransformError.domainElementCountMismatch(
                    domainID: domain.id,
                    expected: domain.estimatedElementCount,
                    actual: actualCount
                )
            }
        }

        try ensurePort(name: architecture.scanEnableSignal, direction: .input, module: &module)
        try ensurePort(name: architecture.testModeSignal, direction: .input, module: &module)

        let sortedIndicesByDomain = cellIndicesByDomain.mapValues { indices in
            indices.sorted { module.cells[$0].instanceName < module.cells[$1].instanceName }
        }
        var transformedCellIDs: [String] = []
        let helperCellIDs: [String] = []

        for chain in plan.chains {
            let count = chain.estimatedElementCount
            let domainIndices = sortedIndicesByDomain[chain.domainID] ?? []
            let offset = plan.chains
                .filter { $0.domainID == chain.domainID && $0.index < chain.index }
                .reduce(0) { $0 + $1.estimatedElementCount }
            let chainIndices = Array(domainIndices[offset ..< offset + count])
            let scanInNet = try ensureNet(
                name: chain.scanInSignal,
                module: &module,
                path: "\(module.name).\(chain.scanInSignal)"
            )
            try ensurePort(name: chain.scanInSignal, direction: .input, module: &module)
            try ensurePort(name: chain.scanOutSignal, direction: .output, module: &module)
            try bindPort(named: chain.scanInSignal, to: scanInNet, module: &module)

            let scanEnableNet = try ensureNet(
                name: architecture.scanEnableSignal,
                module: &module,
                path: "\(module.name).\(architecture.scanEnableSignal)"
            )
            let testModeNet = try ensureNet(
                name: architecture.testModeSignal,
                module: &module,
                path: "\(module.name).\(architecture.testModeSignal)"
            )
            try bindPort(named: architecture.scanEnableSignal, to: scanEnableNet, module: &module)
            try bindPort(named: architecture.testModeSignal, to: testModeNet, module: &module)

            var previousOutputNetID = scanInNet
            for cellIndex in chainIndices {
                var cell = module.cells[cellIndex]
                guard let binding = bindingsByFunctionalType[cell.type] else {
                    throw DFTGateLevelScanTransformError.cellLibraryBindingMissing(
                        instance: cell.instanceName,
                        type: cell.type
                    )
                }
                guard let outputPin = cell.pins.first(where: {
                    $0.name.caseInsensitiveCompare(binding.outputPinName) == .orderedSame
                }) else {
                    throw DFTGateLevelScanTransformError.cellPinContractMissing(
                        instance: cell.instanceName,
                        pin: binding.outputPinName
                    )
                }
                guard binding.scanCellType == policy.scanCellName else {
                    throw DFTGateLevelScanTransformError.scanCellMappingMismatch(
                        functionalType: binding.functionalCellType,
                        expected: binding.scanCellType,
                        actual: policy.scanCellName
                    )
                }
                cell.type = binding.scanCellType
                let scanInPinID = try addOrUpdatePin(
                    name: binding.scanInPinName,
                    direction: .input,
                    netID: previousOutputNetID,
                    cell: &cell
                )
                let scanEnablePinID = try addOrUpdatePin(
                    name: binding.scanEnablePinName,
                    direction: .input,
                    netID: scanEnableNet,
                    cell: &cell
                )
                let testModePinID: String?
                if let testModePinName = binding.testModePinName {
                    testModePinID = try addOrUpdatePin(
                        name: testModePinName,
                        direction: .input,
                        netID: testModeNet,
                        cell: &cell
                    )
                } else {
                    testModePinID = nil
                }
                appendLoad(scanInPinID, to: previousOutputNetID, module: &module)
                appendLoad(scanEnablePinID, to: scanEnableNet, module: &module)
                if let testModePinID {
                    appendLoad(testModePinID, to: testModeNet, module: &module)
                }
                module.cells[cellIndex] = cell
                transformedCellIDs.append(cell.id)
                previousOutputNetID = outputPin.netID ?? previousOutputNetID
            }

            try bindPort(named: chain.scanOutSignal, to: previousOutputNetID, module: &module)
        }

        gate.modules[topIndex] = module
        var transformedSnapshot = snapshot
        transformedSnapshot.gate = gate
        transformedSnapshot.designDigest = nil
        let finalizedSnapshot = try LogicDesignSnapshotCodec.finalized(transformedSnapshot)
        guard let transformedGate = finalizedSnapshot.gate else {
            throw DFTDesignLoaderError.gateDesignMissing
        }
        let validation = LogicDesignValidator().validate(transformedGate)
        guard validation.isValid else {
            throw DFTGateLevelScanTransformError.transformedDesignInvalid(validation.diagnostics)
        }

        return DFTGateLevelScanTransformResult(
            snapshot: finalizedSnapshot,
            transformedCellIDs: transformedCellIDs,
            helperCellIDs: helperCellIDs,
            assumptions: [
                "sequential cell domain assignment follows explicit clock/reset connectivity in the canonical gate IR",
                "cell type recognition remains limited to the declared structural DFF/FF/LATCH naming contract",
                "top-level scan ports use canonical port-to-net bindings without synthetic helper cells",
                "functional ports are preserved"
            ]
        )
    }

    private func isSequential(_ type: String) -> Bool {
        let normalized = type.uppercased()
        return normalized.contains("DFF") || normalized == "FF" || normalized.contains("LATCH")
    }

    private func signalName(
        for cell: GateCell,
        pinNames: [String],
        netsByID: [String: GateNet]
    ) -> String? {
        for pinName in pinNames {
            guard let pin = cell.pins.first(where: { $0.name.uppercased() == pinName }),
                  let netID = pin.netID,
                  let net = netsByID[netID] else {
                continue
            }
            return net.name
        }
        return nil
    }

    private func addOrUpdatePin(
        name: String,
        direction: GatePinDirection,
        netID: String,
        cell: inout GateCell
    ) throws -> String {
        if let index = cell.pins.firstIndex(where: { $0.name.uppercased() == name }) {
            guard cell.pins[index].direction == direction else {
                throw DFTGateLevelScanTransformError.sequentialCellUnsupported(
                    instance: cell.instanceName,
                    type: cell.type
                )
            }
            cell.pins[index].netID = netID
            return cell.pins[index].id
        }
        let id = StableLogicID.make(
            kind: "dft-scan-pin",
            path: cell.id,
            name: name
        )
        cell.pins.append(GatePin(id: id, name: name, direction: direction, netID: netID))
        return id
    }

    private func ensurePort(
        name: String,
        direction: LogicDirection,
        module: inout GateModule
    ) throws {
        if let port = module.ports.first(where: { $0.name == name }) {
            guard port.direction == direction else {
                throw DFTGateLevelScanTransformError.controlPortConflict(name: name)
            }
            return
        }
        let id = StableLogicID.make(kind: "dft-port", path: module.name, name: name)
        module.ports.append(
            RTLPort(
                id: id,
                name: name,
                direction: direction,
                dataType: .logic
            )
        )
    }

    private func ensureExplicitPortBindings(module: inout GateModule) throws {
        var bindings = module.portBindings
        let bindingByPortID = Dictionary(uniqueKeysWithValues: bindings.map { ($0.portID, $0) })
        for port in module.ports where bindingByPortID[port.id] == nil {
            guard let net = module.nets.first(where: {
                $0.name == port.name || $0.id == port.name
            }) else {
                throw DFTGateLevelScanTransformError.portNetMissing(port.name)
            }
            bindings.append(GatePortBinding(portID: port.id, netID: net.id))
        }
        module.portBindings = bindings.sorted { $0.portID < $1.portID }
    }

    private func bindPort(
        named name: String,
        to netID: String,
        module: inout GateModule
    ) throws {
        guard let port = module.ports.first(where: { $0.name == name }) else {
            throw DFTGateLevelScanTransformError.controlPortConflict(name: name)
        }
        var bindings = module.portBindings
        bindings.removeAll { $0.portID == port.id }
        bindings.append(GatePortBinding(portID: port.id, netID: netID))
        module.portBindings = bindings.sorted { $0.portID < $1.portID }
    }

    private func ensureNet(
        name: String,
        module: inout GateModule,
        path: String
    ) throws -> String {
        if let existing = module.nets.first(where: { $0.name == name }) {
            return existing.id
        }
        let id = StableLogicID.make(kind: "dft-net", path: path, name: name)
        guard !module.nets.contains(where: { $0.id == id }) else {
            throw DFTGateLevelScanTransformError.generatedNetConflict(name: name)
        }
        module.nets.append(GateNet(id: id, name: name))
        return id
    }

    private func appendLoad(_ pinID: String, to netID: String, module: inout GateModule) {
        guard let index = module.nets.firstIndex(where: { $0.id == netID }) else { return }
        if !module.nets[index].loadPinIDs.contains(pinID) {
            module.nets[index].loadPinIDs.append(pinID)
        }
    }

}
