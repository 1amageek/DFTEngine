import DFTCore
import Foundation
import LogicIR

public struct DFTGateLevelMemoryBISTTransformer: Sendable {
    public init() {}

    public func transform(
        snapshot: LogicDesignSnapshot,
        configuration: DFTBISTConfiguration,
        mapping: DFTMemoryBISTCellMapping,
        testModeSignal: String
    ) throws -> DFTGateLevelBISTTransformResult {
        guard var gate = snapshot.gate else {
            throw DFTGateLevelMemoryBISTTransformError.gateDesignMissing
        }
        guard let moduleIndex = gate.modules.firstIndex(where: {
            $0.name == gate.topModuleName
        }) else {
            throw DFTGateLevelMemoryBISTTransformError.topModuleMissing(
                gate.topModuleName
            )
        }
        guard let bindings = configuration.memoryBindings, !bindings.isEmpty else {
            throw DFTGateLevelMemoryBISTTransformError.mappingInvalid(
                "macro bindings are missing"
            )
        }
        try validate(configuration: configuration, mapping: mapping, bindings: bindings)

        var module = gate.modules[moduleIndex]
        try ensureExplicitPortBindings(module: &module)
        let testModeNetID = try ensureInputSignal(testModeSignal, module: &module)
        let prefix = "mbist_\(safeIdentifier(configuration.name))"
        let controllerID = "\(prefix)_controller"
        let compactorID = "\(prefix)_response_compactor"
        let signatureID = "\(prefix)_signature_register"
        for id in [controllerID, compactorID, signatureID] {
            try ensureNewCellID(id, module: module)
        }

        var generatedCellIDs: [String] = []
        var generatedNetNames: [String] = []
        var controllerPins: [GatePin] = [
            GatePin(
                id: "\(controllerID)_mode",
                name: "TEST_MODE",
                direction: .input,
                netID: testModeNetID
            )
        ]
        appendLoad("\(controllerID)_mode", to: testModeNetID, module: &module)
        var responseNetIDs: [String] = []
        var clockNetID: String?

        for binding in bindings.sorted(by: { $0.instanceName < $1.instanceName }) {
            guard let macroIndex = module.cells.firstIndex(where: {
                $0.instanceName == binding.instanceName
            }) else {
                throw DFTGateLevelMemoryBISTTransformError.macroMissing(
                    binding.instanceName
                )
            }
            guard module.cells[macroIndex].type == binding.macroType else {
                throw DFTGateLevelMemoryBISTTransformError.macroTypeMismatch(
                    instance: binding.instanceName,
                    expected: binding.macroType,
                    actual: module.cells[macroIndex].type
                )
            }
            let macroClockNetID = try requirePinNet(
                binding.clockPinName,
                direction: .input,
                cell: module.cells[macroIndex]
            )
            if let clockNetID, clockNetID != macroClockNetID {
                throw DFTGateLevelMemoryBISTTransformError.clockDomainMismatch
            }
            clockNetID = macroClockNetID

            if let resetPinName = binding.resetPinName {
                _ = try requirePinNet(
                    resetPinName,
                    direction: .input,
                    cell: module.cells[macroIndex]
                )
            }
            if let testModePinName = binding.testModePinName {
                let pinIndex = try requirePinIndex(
                    testModePinName,
                    direction: .input,
                    cell: module.cells[macroIndex]
                )
                let pinID = module.cells[macroIndex].pins[pinIndex].id
                let previousNetID = module.cells[macroIndex].pins[pinIndex].netID
                if let previousNetID {
                    removeLoad(pinID, from: previousNetID, module: &module)
                }
                module.cells[macroIndex].pins[pinIndex].netID = testModeNetID
                appendLoad(pinID, to: testModeNetID, module: &module)
            }

            let drivenPins = [
                binding.enablePinName,
                binding.writeEnablePinName,
            ] + binding.addressPinNames + binding.dataInputPinNames
            for pinName in drivenPins {
                let pinIndex = try requirePinIndex(
                    pinName,
                    direction: .input,
                    cell: module.cells[macroIndex]
                )
                guard let functionalNetID = module.cells[macroIndex].pins[pinIndex].netID else {
                    throw DFTGateLevelMemoryBISTTransformError.pinNetMissing(
                        instance: binding.instanceName,
                        pin: pinName
                    )
                }
                let token = safeIdentifier("\(binding.instanceName)_\(pinName)")
                let controllerNetID = try appendNet(
                    "\(prefix)_\(token)_controller",
                    module: &module
                )
                let targetNetID = try appendNet(
                    "\(prefix)_\(token)_target",
                    module: &module
                )
                generatedNetNames.append(contentsOf: [
                    "\(prefix)_\(token)_controller",
                    "\(prefix)_\(token)_target",
                ])
                let controllerPinID = "\(controllerID)_\(token)"
                controllerPins.append(GatePin(
                    id: controllerPinID,
                    name: "DRIVE_\(token.uppercased())",
                    direction: .output,
                    netID: controllerNetID
                ))
                appendDriver(controllerPinID, to: controllerNetID, module: &module)

                let muxID = "\(prefix)_\(token)_mux"
                try ensureNewCellID(muxID, module: module)
                let functionalPinID = "\(muxID)_functional"
                let bistPinID = "\(muxID)_bist"
                let selectPinID = "\(muxID)_select"
                let outputPinID = "\(muxID)_output"
                module.cells.append(GateCell(
                    id: muxID,
                    type: mapping.inputMuxCellType,
                    instanceName: muxID,
                    pins: [
                        GatePin(
                            id: functionalPinID,
                            name: "FUNC",
                            direction: .input,
                            netID: functionalNetID
                        ),
                        GatePin(
                            id: bistPinID,
                            name: "BIST",
                            direction: .input,
                            netID: controllerNetID
                        ),
                        GatePin(
                            id: selectPinID,
                            name: "TEST_MODE",
                            direction: .input,
                            netID: testModeNetID
                        ),
                        GatePin(
                            id: outputPinID,
                            name: "Y",
                            direction: .output,
                            netID: targetNetID
                        ),
                    ]
                ))
                generatedCellIDs.append(muxID)
                let targetPinID = module.cells[macroIndex].pins[pinIndex].id
                removeLoad(targetPinID, from: functionalNetID, module: &module)
                appendLoad(functionalPinID, to: functionalNetID, module: &module)
                appendLoad(bistPinID, to: controllerNetID, module: &module)
                appendLoad(selectPinID, to: testModeNetID, module: &module)
                appendDriver(outputPinID, to: targetNetID, module: &module)
                appendLoad(targetPinID, to: targetNetID, module: &module)
                module.cells[macroIndex].pins[pinIndex].netID = targetNetID
            }

            for pinName in binding.dataOutputPinNames {
                let netID = try requirePinNet(
                    pinName,
                    direction: .output,
                    cell: module.cells[macroIndex]
                )
                responseNetIDs.append(netID)
            }
        }

        guard let clockNetID else {
            throw DFTGateLevelMemoryBISTTransformError.clockDomainMismatch
        }
        controllerPins.append(GatePin(
            id: "\(controllerID)_clock",
            name: "CLK",
            direction: .input,
            netID: clockNetID
        ))
        appendLoad("\(controllerID)_clock", to: clockNetID, module: &module)
        let doneNetID = try appendNet("\(prefix)_done", module: &module)
        generatedNetNames.append("\(prefix)_done")
        controllerPins.append(GatePin(
            id: "\(controllerID)_done",
            name: "DONE",
            direction: .output,
            netID: doneNetID
        ))
        appendDriver("\(controllerID)_done", to: doneNetID, module: &module)
        module.cells.append(GateCell(
            id: controllerID,
            type: mapping.controllerCellType,
            instanceName: configuration.controllerCellName,
            pins: controllerPins,
            parameters: [
                GateCellParameter(
                    name: "patternCount",
                    value: .unsignedInteger(UInt64(configuration.patternCount))
                ),
                GateCellParameter(
                    name: "algorithmIDs",
                    value: .string(bindings.map(\.algorithmID).sorted().joined(separator: ","))
                ),
            ]
        ))
        generatedCellIDs.append(controllerID)

        let responseNetID = try appendNet("\(prefix)_response", module: &module)
        generatedNetNames.append("\(prefix)_response")
        var compactorPins = responseNetIDs.enumerated().map { index, netID in
            GatePin(
                id: "\(compactorID)_input_\(index)",
                name: "I\(index)",
                direction: .input,
                netID: netID
            )
        }
        for pin in compactorPins {
            if let netID = pin.netID {
                appendLoad(pin.id, to: netID, module: &module)
            }
        }
        compactorPins.append(GatePin(
            id: "\(compactorID)_output",
            name: "Y",
            direction: .output,
            netID: responseNetID
        ))
        appendDriver("\(compactorID)_output", to: responseNetID, module: &module)
        module.cells.append(GateCell(
            id: compactorID,
            type: mapping.responseCompactorCellType,
            instanceName: compactorID,
            pins: compactorPins
        ))
        generatedCellIDs.append(compactorID)

        let signatureNetID = try appendNet("\(prefix)_signature", module: &module)
        generatedNetNames.append("\(prefix)_signature")
        let signaturePins = [
            GatePin(
                id: "\(signatureID)_data",
                name: "DATA",
                direction: .input,
                netID: responseNetID
            ),
            GatePin(
                id: "\(signatureID)_clock",
                name: "CLK",
                direction: .input,
                netID: clockNetID
            ),
            GatePin(
                id: "\(signatureID)_mode",
                name: "TEST_MODE",
                direction: .input,
                netID: testModeNetID
            ),
            GatePin(
                id: "\(signatureID)_output",
                name: "Q",
                direction: .output,
                netID: signatureNetID
            ),
        ]
        appendLoad(signaturePins[0].id, to: responseNetID, module: &module)
        appendLoad(signaturePins[1].id, to: clockNetID, module: &module)
        appendLoad(signaturePins[2].id, to: testModeNetID, module: &module)
        appendDriver(signaturePins[3].id, to: signatureNetID, module: &module)
        module.cells.append(GateCell(
            id: signatureID,
            type: mapping.signatureRegisterCellType,
            instanceName: configuration.signatureRegisterName,
            pins: signaturePins
        ))
        generatedCellIDs.append(signatureID)
        try ensureOutputSignal("\(prefix)_done", netID: doneNetID, module: &module)
        try ensureOutputSignal(
            "\(prefix)_signature",
            netID: signatureNetID,
            module: &module
        )

        gate.modules[moduleIndex] = module
        let validation = LogicDesignValidator().validate(gate)
        guard validation.isValid else {
            let message = validation.diagnostics
                .filter { $0.severity == .error }
                .map { "\($0.code): \($0.message)" }
                .joined(separator: "; ")
            throw DFTGateLevelMemoryBISTTransformError.transformedDesignInvalid(message)
        }
        let transformed = try LogicDesignSnapshotCodec.finalized(
            LogicDesignSnapshot(rtl: snapshot.rtl, gate: gate)
        )
        return DFTGateLevelBISTTransformResult(
            snapshot: transformed,
            transformedTargetInstances: bindings.map(\.instanceName).sorted(),
            generatedCellIDs: generatedCellIDs,
            generatedNetNames: generatedNetNames
        )
    }

    private func validate(
        configuration: DFTBISTConfiguration,
        mapping: DFTMemoryBISTCellMapping,
        bindings: [DFTMemoryBISTBinding]
    ) throws {
        let names = bindings.map(\.instanceName)
        guard Set(names).count == names.count else {
            throw DFTGateLevelMemoryBISTTransformError.duplicateBinding(
                names.first { name in names.filter { $0 == name }.count > 1 } ?? "<unknown>"
            )
        }
        guard Set(names) == Set(configuration.targetInstances) else {
            throw DFTGateLevelMemoryBISTTransformError.targetSetMismatch
        }
        let cellTypes = [
            mapping.controllerCellType,
            mapping.inputMuxCellType,
            mapping.responseCompactorCellType,
            mapping.signatureRegisterCellType,
        ]
        guard mapping.processID.isEmpty == false,
              mapping.pdkDigest.isEmpty == false,
              mapping.controllerCellType == configuration.controllerCellName,
              cellTypes.allSatisfy({ !$0.isEmpty }) else {
            throw DFTGateLevelMemoryBISTTransformError.mappingInvalid(
                "process identity or helper-cell contract is incomplete"
            )
        }
        for binding in bindings {
            guard mapping.supportedMacroTypes.contains(binding.macroType) else {
                throw DFTGateLevelMemoryBISTTransformError.unsupportedMacroType(
                    binding.macroType
                )
            }
            guard mapping.supportedAlgorithmIDs.contains(binding.algorithmID) else {
                throw DFTGateLevelMemoryBISTTransformError.unsupportedAlgorithm(
                    binding.algorithmID
                )
            }
        }
    }

    private func requirePinIndex(
        _ name: String,
        direction: GatePinDirection,
        cell: GateCell
    ) throws -> Int {
        guard let index = cell.pins.firstIndex(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            throw DFTGateLevelMemoryBISTTransformError.pinMissing(
                instance: cell.instanceName,
                pin: name
            )
        }
        guard cell.pins[index].direction == direction else {
            throw DFTGateLevelMemoryBISTTransformError.pinDirectionInvalid(
                instance: cell.instanceName,
                pin: name
            )
        }
        return index
    }

    private func requirePinNet(
        _ name: String,
        direction: GatePinDirection,
        cell: GateCell
    ) throws -> String {
        let index = try requirePinIndex(name, direction: direction, cell: cell)
        guard let netID = cell.pins[index].netID else {
            throw DFTGateLevelMemoryBISTTransformError.pinNetMissing(
                instance: cell.instanceName,
                pin: name
            )
        }
        return netID
    }

    private func ensureInputSignal(
        _ name: String,
        module: inout GateModule
    ) throws -> String {
        let portID: String
        if let port = module.ports.first(where: { $0.name == name }) {
            guard port.direction == .input else {
                throw DFTGateLevelMemoryBISTTransformError.controlSignalConflict(name)
            }
            portID = port.id
        } else {
            portID = "port-\(safeIdentifier(name))"
            module.ports.append(RTLPort(id: portID, name: name, direction: .input))
        }
        let netID: String
        if let net = module.nets.first(where: { $0.name == name || $0.id == name }) {
            netID = net.id
        } else {
            netID = try appendNet("net-\(safeIdentifier(name))", module: &module)
        }
        bind(portID: portID, netID: netID, module: &module)
        return netID
    }

    private func ensureOutputSignal(
        _ name: String,
        netID: String,
        module: inout GateModule
    ) throws {
        let portID: String
        if let port = module.ports.first(where: { $0.name == name }) {
            guard port.direction == .output else {
                throw DFTGateLevelMemoryBISTTransformError.controlSignalConflict(name)
            }
            portID = port.id
        } else {
            portID = "port-\(safeIdentifier(name))"
            module.ports.append(RTLPort(id: portID, name: name, direction: .output))
        }
        bind(portID: portID, netID: netID, module: &module)
    }

    private func ensureExplicitPortBindings(module: inout GateModule) throws {
        let boundPortIDs = Set(module.portBindings.map(\.portID))
        for port in module.ports where !boundPortIDs.contains(port.id) {
            guard let net = module.nets.first(where: {
                $0.name == port.name || $0.id == port.name
            }) else {
                throw DFTGateLevelMemoryBISTTransformError.pinNetMissing(
                    instance: module.name,
                    pin: port.name
                )
            }
            module.portBindings.append(GatePortBinding(
                portID: port.id,
                netID: net.id
            ))
        }
    }

    private func appendNet(
        _ name: String,
        module: inout GateModule
    ) throws -> String {
        guard !module.nets.contains(where: { $0.id == name || $0.name == name }) else {
            throw DFTGateLevelMemoryBISTTransformError.generatedNameCollision(name)
        }
        module.nets.append(GateNet(id: name, name: name))
        return name
    }

    private func ensureNewCellID(_ id: String, module: GateModule) throws {
        guard !module.cells.contains(where: {
            $0.id == id || $0.instanceName == id
        }) else {
            throw DFTGateLevelMemoryBISTTransformError.generatedNameCollision(id)
        }
    }

    private func bind(
        portID: String,
        netID: String,
        module: inout GateModule
    ) {
        module.portBindings.removeAll { $0.portID == portID }
        module.portBindings.append(GatePortBinding(portID: portID, netID: netID))
    }

    private func appendLoad(
        _ pinID: String,
        to netID: String,
        module: inout GateModule
    ) {
        guard let index = module.nets.firstIndex(where: { $0.id == netID }) else { return }
        if !module.nets[index].loadPinIDs.contains(pinID) {
            module.nets[index].loadPinIDs.append(pinID)
        }
    }

    private func removeLoad(
        _ pinID: String,
        from netID: String,
        module: inout GateModule
    ) {
        guard let index = module.nets.firstIndex(where: { $0.id == netID }) else { return }
        module.nets[index].loadPinIDs.removeAll { $0 == pinID }
    }

    private func appendDriver(
        _ pinID: String,
        to netID: String,
        module: inout GateModule
    ) {
        guard let index = module.nets.firstIndex(where: { $0.id == netID }) else { return }
        if !module.nets[index].driverPinIDs.contains(pinID) {
            module.nets[index].driverPinIDs.append(pinID)
        }
    }

    private func safeIdentifier(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar)
                ? Character(String(scalar))
                : "_"
        }
        let result = String(scalars)
        return result.isEmpty ? "unnamed" : result
    }
}
