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

        var portIndexByName = Dictionary(
            uniqueKeysWithValues: module.ports.indices.map { (module.ports[$0].name, $0) }
        )
        var bindingIndexByPortID = Dictionary(
            uniqueKeysWithValues: module.portBindings.indices.map {
                (module.portBindings[$0].portID, $0)
            }
        )
        try ensurePort(
            name: architecture.scanEnableSignal,
            direction: .input,
            module: &module,
            portIndexByName: &portIndexByName
        )
        try ensurePort(
            name: architecture.testModeSignal,
            direction: .input,
            module: &module,
            portIndexByName: &portIndexByName
        )

        let sortedIndicesByDomain = cellIndicesByDomain.mapValues { indices in
            indices.sorted { module.cells[$0].instanceName < module.cells[$1].instanceName }
        }
        var transformedCellIDs: [String] = []
        var helperCellIDs: [String] = []
        var chainOffsetsByDomain: [String: Int] = [:]
        var chainInputNetIDs: [String] = []
        var chainOutputNetIDs: [String] = []
        var realizedChains: [DFTRealizedScanChain] = []
        let compressionEnabled = architecture.compression?.enabled == true
        var netIndexByID = Dictionary(
            uniqueKeysWithValues: module.nets.indices.map { (module.nets[$0].id, $0) }
        )
        var netIDByName = Dictionary(
            uniqueKeysWithValues: module.nets.map { ($0.name, $0.id) }
        )
        let scanEnableNet = try ensureNet(
            name: architecture.scanEnableSignal,
            module: &module,
            path: "\(module.name).\(architecture.scanEnableSignal)",
            netIndexByID: &netIndexByID,
            netIDByName: &netIDByName
        )
        let testModeNet = try ensureNet(
            name: architecture.testModeSignal,
            module: &module,
            path: "\(module.name).\(architecture.testModeSignal)",
            netIndexByID: &netIndexByID,
            netIDByName: &netIDByName
        )
        try bindPort(
            named: architecture.scanEnableSignal,
            to: scanEnableNet,
            module: &module,
            portIndexByName: portIndexByName,
            bindingIndexByPortID: &bindingIndexByPortID
        )
        try bindPort(
            named: architecture.testModeSignal,
            to: testModeNet,
            module: &module,
            portIndexByName: portIndexByName,
            bindingIndexByPortID: &bindingIndexByPortID
        )

        for chain in plan.chains {
            let count = chain.estimatedElementCount
            let domainIndices = sortedIndicesByDomain[chain.domainID] ?? []
            let offset = chainOffsetsByDomain[chain.domainID, default: 0]
            chainOffsetsByDomain[chain.domainID] = offset + count
            let chainIndices = Array(domainIndices[offset ..< offset + count])
            let scanInNet = try ensureNet(
                name: chain.scanInSignal,
                module: &module,
                path: "\(module.name).\(chain.scanInSignal)",
                netIndexByID: &netIndexByID,
                netIDByName: &netIDByName
            )
            if !compressionEnabled {
                try ensurePort(
                    name: chain.scanInSignal,
                    direction: .input,
                    module: &module,
                    portIndexByName: &portIndexByName
                )
                try ensurePort(
                    name: chain.scanOutSignal,
                    direction: .output,
                    module: &module,
                    portIndexByName: &portIndexByName
                )
                try bindPort(
                    named: chain.scanInSignal,
                    to: scanInNet,
                    module: &module,
                    portIndexByName: portIndexByName,
                    bindingIndexByPortID: &bindingIndexByPortID
                )
            }

            var previousOutputNetID = scanInNet
            var realizedElements: [DFTScanElementBinding] = []
            for (position, cellIndex) in chainIndices.enumerated() {
                var cell = module.cells[cellIndex]
                guard let binding = bindingsByFunctionalType[cell.type] else {
                    throw DFTGateLevelScanTransformError.cellLibraryBindingMissing(
                        instance: cell.instanceName,
                        type: cell.type
                    )
                }
                guard let outputPin = cell.pins.first(where: {
                    $0.name.caseInsensitiveCompare(binding.outputPinName) == .orderedSame
                }),
                      let outputNetID = outputPin.netID,
                      let dataPin = cell.pins.first(where: {
                          $0.name.caseInsensitiveCompare(binding.dataPinName) == .orderedSame
                      }),
                      let dataNetID = dataPin.netID,
                      let clockPin = cell.pins.first(where: { pin in
                          binding.clockPinNames.contains {
                              $0.caseInsensitiveCompare(pin.name) == .orderedSame
                          }
                      }),
                      let clockNetID = clockPin.netID else {
                    throw DFTGateLevelScanTransformError.cellPinContractMissing(
                        instance: cell.instanceName,
                        pin: "data/output/clock"
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
                appendLoad(
                    scanInPinID,
                    to: previousOutputNetID,
                    module: &module,
                    netIndexByID: netIndexByID
                )
                appendLoad(
                    scanEnablePinID,
                    to: scanEnableNet,
                    module: &module,
                    netIndexByID: netIndexByID
                )
                if let testModePinID {
                    appendLoad(
                        testModePinID,
                        to: testModeNet,
                        module: &module,
                        netIndexByID: netIndexByID
                    )
                }
                module.cells[cellIndex] = cell
                transformedCellIDs.append(cell.id)
                realizedElements.append(DFTScanElementBinding(
                    position: position,
                    cellID: cell.id,
                    instanceName: cell.instanceName,
                    cellType: cell.type,
                    dataPinName: binding.dataPinName,
                    dataNetID: dataNetID,
                    outputPinName: binding.outputPinName,
                    outputNetID: outputNetID,
                    clockPinName: clockPin.name,
                    clockNetID: clockNetID,
                    scanInPinName: binding.scanInPinName,
                    scanInNetID: previousOutputNetID,
                    scanEnablePinName: binding.scanEnablePinName,
                    scanEnableNetID: scanEnableNet,
                    testModePinName: binding.testModePinName,
                    testModeNetID: binding.testModePinName == nil ? nil : testModeNet
                ))
                previousOutputNetID = outputNetID
            }

            chainInputNetIDs.append(scanInNet)
            chainOutputNetIDs.append(previousOutputNetID)
            realizedChains.append(DFTRealizedScanChain(
                chainID: chain.id,
                domainID: chain.domainID,
                scanInSignal: chain.scanInSignal,
                scanInNetID: scanInNet,
                scanOutSignal: chain.scanOutSignal,
                scanOutNetID: previousOutputNetID,
                elements: realizedElements
            ))
            if !compressionEnabled {
                try bindPort(
                    named: chain.scanOutSignal,
                    to: previousOutputNetID,
                    module: &module,
                    portIndexByName: portIndexByName,
                    bindingIndexByPortID: &bindingIndexByPortID
                )
            }
        }
        module.portBindings.sort { $0.portID < $1.portID }

        if let compression = architecture.compression, compression.enabled {
            helperCellIDs = try DFTGateLevelScanCompressionTransformer().transform(
                module: &module,
                configuration: compression,
                mapping: cellLibrary.scanCompressionMapping,
                chainInputNetIDs: chainInputNetIDs,
                chainOutputNetIDs: chainOutputNetIDs
            )
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
        guard let transformedDesignDigest = finalizedSnapshot.designDigest else {
            throw DFTGateLevelScanTransformError.transformedDesignInvalid([
                LogicDiagnostic(
                    severity: .error,
                    code: "DFT_TRANSFORMED_DIGEST_MISSING",
                    message: "The finalized scan design has no canonical digest."
                )
            ])
        }
        let sourceDesignDigest = try LogicDesignSnapshotCodec.digest(snapshot)
        let scanImplementation = DFTScanImplementation(
            architectureName: architecture.name,
            sourceDesignDigest: sourceDesignDigest,
            transformedDesignDigest: transformedDesignDigest,
            scanEnableSignal: architecture.scanEnableSignal,
            scanEnableNetID: try scanEnableNetID(
                named: architecture.scanEnableSignal,
                in: transformedGate.modules[topIndex]
            ),
            testModeSignal: architecture.testModeSignal,
            testModeNetID: try scanEnableNetID(
                named: architecture.testModeSignal,
                in: transformedGate.modules[topIndex]
            ),
            chains: realizedChains
        )

        return DFTGateLevelScanTransformResult(
            snapshot: finalizedSnapshot,
            transformedCellIDs: transformedCellIDs,
            helperCellIDs: helperCellIDs,
            scanImplementation: scanImplementation,
            assumptions: [
                "sequential cell domain assignment follows explicit clock/reset connectivity in the canonical gate IR",
                "cell type recognition remains limited to the declared structural DFF/FF/LATCH naming contract",
                compressionEnabled
                    ? "top-level compressed scan channels are mapped explicitly through decompressor and compactor helper cells"
                    : "top-level scan ports use canonical port-to-net bindings without synthetic helper cells",
                "functional ports are preserved"
            ]
        )
    }

    private func scanEnableNetID(
        named signalName: String,
        in module: GateModule
    ) throws -> String {
        guard let port = module.ports.first(where: { $0.name == signalName }),
              let binding = module.portBindings.first(where: { $0.portID == port.id }) else {
            throw DFTGateLevelScanTransformError.controlPortConflict(name: signalName)
        }
        return binding.netID
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
        module: inout GateModule,
        portIndexByName: inout [String: Int]
    ) throws {
        if let index = portIndexByName[name] {
            let port = module.ports[index]
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
        portIndexByName[name] = module.ports.index(before: module.ports.endIndex)
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
        module: inout GateModule,
        portIndexByName: [String: Int],
        bindingIndexByPortID: inout [String: Int]
    ) throws {
        guard let portIndex = portIndexByName[name] else {
            throw DFTGateLevelScanTransformError.controlPortConflict(name: name)
        }
        let portID = module.ports[portIndex].id
        let binding = GatePortBinding(portID: portID, netID: netID)
        if let bindingIndex = bindingIndexByPortID[portID] {
            module.portBindings[bindingIndex] = binding
        } else {
            module.portBindings.append(binding)
            bindingIndexByPortID[portID] = module.portBindings.index(
                before: module.portBindings.endIndex
            )
        }
    }

    private func ensureNet(
        name: String,
        module: inout GateModule,
        path: String,
        netIndexByID: inout [String: Int],
        netIDByName: inout [String: String]
    ) throws -> String {
        if let existingID = netIDByName[name] {
            return existingID
        }
        let id = StableLogicID.make(kind: "dft-net", path: path, name: name)
        guard netIndexByID[id] == nil else {
            throw DFTGateLevelScanTransformError.generatedNetConflict(name: name)
        }
        module.nets.append(GateNet(id: id, name: name))
        netIndexByID[id] = module.nets.index(before: module.nets.endIndex)
        netIDByName[name] = id
        return id
    }

    private func appendLoad(
        _ pinID: String,
        to netID: String,
        module: inout GateModule,
        netIndexByID: [String: Int]
    ) {
        guard let index = netIndexByID[netID] else { return }
        if !module.nets[index].loadPinIDs.contains(pinID) {
            module.nets[index].loadPinIDs.append(pinID)
        }
    }

}
