import Foundation
import DFTCore
import LogicIR

public struct DFTGateLevelBISTTransformer: Sendable {
    public init() {}

    public func transform(
        snapshot: LogicDesignSnapshot,
        configuration: DFTBISTConfiguration,
        testModeSignal: String,
        clockSignal: String
    ) throws -> DFTGateLevelBISTTransformResult {
        guard configuration.kind == .logic else {
            throw DFTGateLevelBISTTransformError.unsupportedKind(configuration.kind)
        }
        guard let gate = snapshot.gate else {
            throw DFTGateLevelBISTTransformError.gateDesignMissing
        }
        guard let moduleIndex = gate.modules.firstIndex(where: { $0.name == gate.topModuleName }) else {
            throw DFTGateLevelBISTTransformError.topModuleMissing(gate.topModuleName)
        }
        guard let bindings = configuration.targetBindings, !bindings.isEmpty else {
            throw DFTGateLevelBISTTransformError.targetBindingsMissing
        }
        guard let cellMapping = configuration.logicCellMapping else {
            throw DFTGateLevelBISTTransformError.cellMappingMissing
        }
        try validate(cellMapping: cellMapping, configuration: configuration)
        let bindingNames = bindings.map(\.instanceName)
        guard Set(bindingNames).count == bindingNames.count else {
            let duplicate = bindingNames.first { name in bindingNames.filter { $0 == name }.count > 1 } ?? "<unknown>"
            throw DFTGateLevelBISTTransformError.duplicateTargetBinding(duplicate)
        }
        guard Set(configuration.targetInstances) == Set(bindingNames),
              !configuration.targetInstances.isEmpty else {
            throw DFTGateLevelBISTTransformError.targetSetMismatch
        }

        var transformedGate = gate
        var module = transformedGate.modules[moduleIndex]
        try ensureExplicitPortBindings(module: &module)
        guard module.nets.contains(where: { $0.name == clockSignal || $0.id == clockSignal }) else {
            throw DFTGateLevelBISTTransformError.clockNetMissing(clockSignal)
        }
        let clockNet = module.nets.first { $0.name == clockSignal || $0.id == clockSignal }
        guard let clockNet else {
            throw DFTGateLevelBISTTransformError.clockNetMissing(clockSignal)
        }
        let testModeNetID = try ensureInputControlSignal(
            named: testModeSignal,
            module: &module
        )
        let prefix = "bist_\(safeIdentifier(configuration.name))"
        let patternNetID = try appendNet(
            id: "\(prefix)_pattern",
            name: "\(prefix)_pattern",
            to: &module
        )
        let doneNetID = try appendNet(
            id: "\(prefix)_done",
            name: "\(prefix)_done",
            to: &module
        )
        let responseNetID = try appendNet(
            id: "\(prefix)_response",
            name: "\(prefix)_response",
            to: &module
        )
        let signatureNetID = try appendNet(
            id: "\(prefix)_signature",
            name: "\(prefix)_signature",
            to: &module
        )
        let controllerID = "\(prefix)_controller"
        let signatureID = "\(prefix)_signature_register"
        try ensureNewCellID(controllerID, in: module)
        try ensureNewCellID(signatureID, in: module)

        var generatedCellIDs = [controllerID, signatureID]
        var generatedNetNames = [
            "\(prefix)_pattern",
            "\(prefix)_done",
            "\(prefix)_response",
            "\(prefix)_signature",
        ]
        var transformedTargets: [String] = []
        var captureNetIDs: [String] = []

        for binding in bindings.sorted(by: { $0.instanceName < $1.instanceName }) {
            guard let targetIndex = module.cells.firstIndex(where: { $0.instanceName == binding.instanceName }) else {
                throw DFTGateLevelBISTTransformError.targetInstanceMissing(binding.instanceName)
            }
            guard !binding.patternInputPinNames.isEmpty,
                  !binding.responseOutputPinNames.isEmpty else {
                throw DFTGateLevelBISTTransformError.targetPinSetEmpty(binding.instanceName)
            }
            transformedTargets.append(binding.instanceName)

            for pinName in binding.patternInputPinNames {
                guard let pinIndex = pinIndex(named: pinName, in: module.cells[targetIndex].pins) else {
                    throw DFTGateLevelBISTTransformError.pinMissing(instance: binding.instanceName, pin: pinName)
                }
                let targetPin = module.cells[targetIndex].pins[pinIndex]
                guard targetPin.direction == .input else {
                    throw DFTGateLevelBISTTransformError.pinDirectionInvalid(instance: binding.instanceName, pin: pinName)
                }
                guard let originalNetID = targetPin.netID else {
                    throw DFTGateLevelBISTTransformError.pinNetMissing(instance: binding.instanceName, pin: pinName)
                }
                guard module.nets.contains(where: { $0.id == originalNetID }) else {
                    throw DFTGateLevelBISTTransformError.netMissing(originalNetID)
                }

                let token = safeIdentifier("\(binding.instanceName)_\(pinName)")
                let targetNetID = try appendNet(
                    id: "\(prefix)_\(token)_target",
                    name: "\(prefix)_\(token)_target",
                    to: &module
                )
                generatedNetNames.append("\(prefix)_\(token)_target")
                let muxID = "\(prefix)_\(token)_input_mux"
                try ensureNewCellID(muxID, in: module)
                let funcPinID = "\(muxID)_func"
                let bistPinID = "\(muxID)_bist"
                let modePinID = "\(muxID)_mode"
                let outputPinID = "\(muxID)_out"
                let mux = GateCell(
                    id: muxID,
                    type: cellMapping.inputMuxCellType,
                    instanceName: muxID,
                    pins: [
                        GatePin(id: funcPinID, name: "FUNC", direction: .input, netID: originalNetID),
                        GatePin(id: bistPinID, name: "BIST", direction: .input, netID: patternNetID),
                        GatePin(id: modePinID, name: "TEST_MODE", direction: .input, netID: testModeNetID),
                        GatePin(id: outputPinID, name: "Y", direction: .output, netID: targetNetID),
                    ]
                )
                module.cells.append(mux)
                generatedCellIDs.append(muxID)
                updateNet(originalNetID, in: &module) { net in
                    net.loadPinIDs.removeAll { $0 == targetPin.id }
                    if !net.loadPinIDs.contains(funcPinID) { net.loadPinIDs.append(funcPinID) }
                }
                updateNet(patternNetID, in: &module) { net in
                    if !net.loadPinIDs.contains(bistPinID) { net.loadPinIDs.append(bistPinID) }
                }
                updateNet(testModeNetID, in: &module) { net in
                    if !net.loadPinIDs.contains(modePinID) { net.loadPinIDs.append(modePinID) }
                }
                updateNet(targetNetID, in: &module) { net in
                    if !net.driverPinIDs.contains(outputPinID) { net.driverPinIDs.append(outputPinID) }
                    if !net.loadPinIDs.contains(targetPin.id) { net.loadPinIDs.append(targetPin.id) }
                }
                module.cells[targetIndex].pins[pinIndex].netID = targetNetID
            }

            for (captureIndex, pinName) in binding.responseOutputPinNames.enumerated() {
                guard let pinIndex = pinIndex(named: pinName, in: module.cells[targetIndex].pins) else {
                    throw DFTGateLevelBISTTransformError.pinMissing(instance: binding.instanceName, pin: pinName)
                }
                let targetPin = module.cells[targetIndex].pins[pinIndex]
                guard targetPin.direction == .output else {
                    throw DFTGateLevelBISTTransformError.pinDirectionInvalid(instance: binding.instanceName, pin: pinName)
                }
                guard let originalNetID = targetPin.netID else {
                    throw DFTGateLevelBISTTransformError.pinNetMissing(instance: binding.instanceName, pin: pinName)
                }
                guard module.nets.contains(where: { $0.id == originalNetID }) else {
                    throw DFTGateLevelBISTTransformError.netMissing(originalNetID)
                }
                let token = safeIdentifier("\(binding.instanceName)_\(pinName)_\(captureIndex)")
                let captureNetID = try appendNet(
                    id: "\(prefix)_\(token)_capture",
                    name: "\(prefix)_\(token)_capture",
                    to: &module
                )
                generatedNetNames.append("\(prefix)_\(token)_capture")
                let captureID = "\(prefix)_\(token)_capture_cell"
                try ensureNewCellID(captureID, in: module)
                let inputPinID = "\(captureID)_in"
                let outputPinID = "\(captureID)_out"
                module.cells.append(GateCell(
                    id: captureID,
                    type: cellMapping.responseCaptureCellType,
                    instanceName: captureID,
                    pins: [
                        GatePin(id: inputPinID, name: "I", direction: .input, netID: originalNetID),
                        GatePin(id: outputPinID, name: "O", direction: .output, netID: captureNetID),
                    ]
                ))
                generatedCellIDs.append(captureID)
                updateNet(originalNetID, in: &module) { net in
                    if !net.loadPinIDs.contains(inputPinID) { net.loadPinIDs.append(inputPinID) }
                }
                updateNet(captureNetID, in: &module) { net in
                    if !net.driverPinIDs.contains(outputPinID) { net.driverPinIDs.append(outputPinID) }
                }
                captureNetIDs.append(captureNetID)
            }
        }

        let compactorID = "\(prefix)_response_compactor"
        try ensureNewCellID(compactorID, in: module)
        let compactorInputPins = captureNetIDs.enumerated().map { index, netID in
            GatePin(id: "\(compactorID)_in_\(index)", name: "I\(index)", direction: .input, netID: netID)
        }
        let compactorOutputID = "\(compactorID)_out"
        module.cells.append(GateCell(
            id: compactorID,
            type: cellMapping.responseCompactorCellType,
            instanceName: compactorID,
            pins: compactorInputPins + [GatePin(id: compactorOutputID, name: "Y", direction: .output, netID: responseNetID)]
        ))
        generatedCellIDs.append(compactorID)
        for pin in compactorInputPins {
            if let netID = pin.netID {
                updateNet(netID, in: &module) { net in
                    if !net.loadPinIDs.contains(pin.id) { net.loadPinIDs.append(pin.id) }
                }
            }
        }
        updateNet(responseNetID, in: &module) { net in
            if !net.driverPinIDs.contains(compactorOutputID) { net.driverPinIDs.append(compactorOutputID) }
        }

        let controllerPins = [
            GatePin(id: "\(controllerID)_mode", name: "TEST_MODE", direction: .input, netID: testModeNetID),
            GatePin(id: "\(controllerID)_clock", name: "CLK", direction: .input, netID: clockNet.id),
            GatePin(id: "\(controllerID)_pattern", name: "PATTERN", direction: .output, netID: patternNetID),
            GatePin(id: "\(controllerID)_done", name: "DONE", direction: .output, netID: doneNetID),
        ]
        module.cells.append(GateCell(
            id: controllerID,
            type: cellMapping.controllerCellType,
            instanceName: controllerID,
            pins: controllerPins
        ))
        updateNet(testModeNetID, in: &module) { net in net.loadPinIDs.append(controllerPins[0].id) }
        updateNet(clockNet.id, in: &module) { net in net.loadPinIDs.append(controllerPins[1].id) }
        updateNet(patternNetID, in: &module) { net in net.driverPinIDs.append(controllerPins[2].id) }
        updateNet(doneNetID, in: &module) { net in net.driverPinIDs.append(controllerPins[3].id) }

        let signaturePins = [
            GatePin(id: "\(signatureID)_data", name: "DATA", direction: .input, netID: responseNetID),
            GatePin(id: "\(signatureID)_clock", name: "CLK", direction: .input, netID: clockNet.id),
            GatePin(id: "\(signatureID)_mode", name: "TEST_MODE", direction: .input, netID: testModeNetID),
            GatePin(id: "\(signatureID)_q", name: "Q", direction: .output, netID: signatureNetID),
        ]
        module.cells.append(GateCell(
            id: signatureID,
            type: cellMapping.signatureRegisterCellType,
            instanceName: configuration.signatureRegisterName,
            pins: signaturePins
        ))
        updateNet(responseNetID, in: &module) { net in net.loadPinIDs.append(signaturePins[0].id) }
        updateNet(clockNet.id, in: &module) { net in net.loadPinIDs.append(signaturePins[1].id) }
        updateNet(testModeNetID, in: &module) { net in net.loadPinIDs.append(signaturePins[2].id) }
        updateNet(signatureNetID, in: &module) { net in net.driverPinIDs.append(signaturePins[3].id) }

        try appendOutputPortIfNeeded(name: "\(prefix)_done", netID: doneNetID, module: &module)
        try appendOutputPortIfNeeded(name: "\(prefix)_signature", netID: signatureNetID, module: &module)
        transformedGate.modules[moduleIndex] = module
        let validation = LogicDesignValidator().validate(transformedGate)
        guard validation.isValid else {
            let message = validation.diagnostics
                .filter { $0.severity == .error }
                .map { "\($0.code): \($0.message)" }
                .joined(separator: "; ")
            throw DFTGateLevelBISTTransformError.transformedDesignInvalid(message)
        }
        let transformedSnapshot = try LogicDesignSnapshotCodec.finalized(
            LogicDesignSnapshot(rtl: snapshot.rtl, gate: transformedGate)
        )
        return DFTGateLevelBISTTransformResult(
            snapshot: transformedSnapshot,
            transformedTargetInstances: transformedTargets.sorted(),
            generatedCellIDs: generatedCellIDs,
            generatedNetNames: generatedNetNames
        )
    }

    private func pinIndex(named name: String, in pins: [GatePin]) -> Int? {
        pins.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func ensureInputControlSignal(named name: String, module: inout GateModule) throws -> String {
        let port: RTLPort
        if let existing = module.ports.first(where: { $0.name == name }) {
            guard existing.direction == .input else {
                throw DFTGateLevelBISTTransformError.controlSignalConflict(name)
            }
            port = existing
        } else {
            port = RTLPort(id: "port-\(safeIdentifier(name))", name: name, direction: .input)
            module.ports.append(port)
        }
        let netID: String
        if let net = module.nets.first(where: { $0.name == name || $0.id == name }) {
            netID = net.id
        } else {
            let id = "net-\(safeIdentifier(name))"
            _ = try appendNet(id: id, name: name, to: &module)
            netID = id
        }
        bind(portID: port.id, to: netID, module: &module)
        return netID
    }

    private func appendNet(id: String, name: String, to module: inout GateModule) throws -> String {
        guard !module.nets.contains(where: { $0.id == id || $0.name == name }) else {
            throw DFTGateLevelBISTTransformError.generatedNameCollision(name)
        }
        module.nets.append(GateNet(id: id, name: name))
        return id
    }

    private func ensureNewCellID(_ id: String, in module: GateModule) throws {
        guard !module.cells.contains(where: { $0.id == id || $0.instanceName == id }) else {
            throw DFTGateLevelBISTTransformError.generatedNameCollision(id)
        }
    }

    private func updateNet(
        _ id: String,
        in module: inout GateModule,
        update: (inout GateNet) -> Void
    ) {
        guard let index = module.nets.firstIndex(where: { $0.id == id }) else { return }
        update(&module.nets[index])
    }

    private func appendOutputPortIfNeeded(
        name: String,
        netID: String,
        module: inout GateModule
    ) throws {
        let port: RTLPort
        if let existing = module.ports.first(where: { $0.name == name }) {
            guard existing.direction == .output else {
                throw DFTGateLevelBISTTransformError.controlSignalConflict(name)
            }
            port = existing
        } else {
            port = RTLPort(id: "port-\(safeIdentifier(name))", name: name, direction: .output)
            module.ports.append(port)
        }
        if !module.nets.contains(where: { $0.id == netID }) {
            module.nets.append(GateNet(id: netID, name: name))
        }
        bind(portID: port.id, to: netID, module: &module)
    }

    private func ensureExplicitPortBindings(module: inout GateModule) throws {
        var bindings = module.portBindings
        let boundPortIDs = Set(bindings.map(\.portID))
        for port in module.ports where !boundPortIDs.contains(port.id) {
            guard let net = module.nets.first(where: {
                $0.name == port.name || $0.id == port.name
            }) else {
                throw DFTGateLevelBISTTransformError.netMissing(port.name)
            }
            bindings.append(GatePortBinding(portID: port.id, netID: net.id))
        }
        module.portBindings = bindings.sorted { $0.portID < $1.portID }
    }

    private func bind(portID: String, to netID: String, module: inout GateModule) {
        var bindings = module.portBindings
        bindings.removeAll { $0.portID == portID }
        bindings.append(GatePortBinding(portID: portID, netID: netID))
        module.portBindings = bindings.sorted { $0.portID < $1.portID }
    }

    private func validate(
        cellMapping: DFTLogicBISTCellMapping,
        configuration: DFTBISTConfiguration
    ) throws {
        let cellTypes = [
            cellMapping.controllerCellType,
            cellMapping.inputMuxCellType,
            cellMapping.responseCaptureCellType,
            cellMapping.responseCompactorCellType,
            cellMapping.signatureRegisterCellType,
        ]
        guard cellTypes.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              cellMapping.controllerCellType == configuration.controllerCellName else {
            throw DFTGateLevelBISTTransformError.cellMappingInvalid("cell type contract mismatch")
        }
        guard !cellMapping.processID.isEmpty,
              !cellMapping.pdkDigest.isEmpty else {
            throw DFTGateLevelBISTTransformError.cellMappingInvalid("process identity is missing")
        }
        guard validPolynomialTaps(cellMapping.prpgPolynomialTaps),
              validPolynomialTaps(cellMapping.misrPolynomialTaps) else {
            throw DFTGateLevelBISTTransformError.cellMappingInvalid("polynomial taps must be unique positive integers")
        }
        guard !cellMapping.expectedSignature.isEmpty,
              cellMapping.expectedSignature.allSatisfy({ $0 == "0" || $0 == "1" }) else {
            throw DFTGateLevelBISTTransformError.cellMappingInvalid("expected signature must be binary")
        }
    }

    private func validPolynomialTaps(_ taps: [Int]) -> Bool {
        !taps.isEmpty && taps.allSatisfy { $0 > 0 } && Set(taps).count == taps.count
    }

    private func safeIdentifier(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(String(scalar)) }
            return "_"
        }
        let result = String(scalars)
        return result.isEmpty ? "unnamed" : result
    }
}
