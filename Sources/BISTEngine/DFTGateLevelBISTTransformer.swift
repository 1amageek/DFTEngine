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
        let bindingNames = bindings.map(\.instanceName)
        guard Set(bindingNames).count == bindingNames.count else {
            let duplicate = bindingNames.first { name in bindingNames.filter { $0 == name }.count > 1 } ?? "<unknown>"
            throw DFTGateLevelBISTTransformError.duplicateTargetBinding(duplicate)
        }

        var transformedGate = gate
        var module = transformedGate.modules[moduleIndex]
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
                    type: "DFT_BIST_INPUT_MUX",
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
                    type: "DFT_BIST_RESPONSE_CAPTURE",
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
            type: "DFT_BIST_RESPONSE_COMPACTOR",
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
            type: configuration.controllerCellName,
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
            type: "DFT_BIST_SIGNATURE_REGISTER",
            instanceName: configuration.signatureRegisterName,
            pins: signaturePins
        ))
        updateNet(responseNetID, in: &module) { net in net.loadPinIDs.append(signaturePins[0].id) }
        updateNet(clockNet.id, in: &module) { net in net.loadPinIDs.append(signaturePins[1].id) }
        updateNet(testModeNetID, in: &module) { net in net.loadPinIDs.append(signaturePins[2].id) }
        updateNet(signatureNetID, in: &module) { net in net.driverPinIDs.append(signaturePins[3].id) }

        appendOutputPortIfNeeded(name: "\(prefix)_done", netID: doneNetID, module: &module)
        appendOutputPortIfNeeded(name: "\(prefix)_signature", netID: signatureNetID, module: &module)
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
        if let existing = module.ports.first(where: { $0.name == name }) {
            guard existing.direction == .input else {
                throw DFTGateLevelBISTTransformError.controlSignalConflict(name)
            }
        } else {
            module.ports.append(RTLPort(id: "port-\(safeIdentifier(name))", name: name, direction: .input))
        }
        if let net = module.nets.first(where: { $0.name == name || $0.id == name }) {
            return net.id
        }
        let id = "net-\(safeIdentifier(name))"
        _ = try appendNet(id: id, name: name, to: &module)
        return id
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

    private func appendOutputPortIfNeeded(name: String, netID: String, module: inout GateModule) {
        if module.ports.contains(where: { $0.name == name }) { return }
        module.ports.append(RTLPort(id: "port-\(safeIdentifier(name))", name: name, direction: .output))
        if !module.nets.contains(where: { $0.id == netID }) {
            module.nets.append(GateNet(id: netID, name: name))
        }
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
