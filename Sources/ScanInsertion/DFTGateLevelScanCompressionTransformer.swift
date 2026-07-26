import DFTCore
import LogicIR

public struct DFTGateLevelScanCompressionTransformer: Sendable {
    public init() {}

    public func transform(
        module: inout GateModule,
        configuration: DFTCompressionConfiguration,
        mapping: DFTScanCompressionCellMapping?,
        chainInputNetIDs: [String],
        chainOutputNetIDs: [String]
    ) throws -> [String] {
        guard let mapping,
              !mapping.decompressorCellType.isEmpty,
              !mapping.compactorCellType.isEmpty,
              configuration.scanInputSignals.count == mapping.decompressorInputPinNames.count,
              configuration.scanOutputSignals.count == mapping.compactorOutputPinNames.count,
              mapping.decompressorOutputPinNames.count == chainInputNetIDs.count,
              mapping.compactorInputPinNames.count == chainOutputNetIDs.count,
              validPinNames(mapping.decompressorInputPinNames),
              validPinNames(mapping.decompressorOutputPinNames),
              validPinNames(mapping.compactorInputPinNames),
              validPinNames(mapping.compactorOutputPinNames) else {
            throw DFTGateLevelScanTransformError.compressionConfigurationInvalid(
                "the process-bound cell-library mapping must cover every external channel and internal chain"
            )
        }

        let decompressorID = StableLogicID.make(
            kind: "dft-scan-decompressor",
            path: module.name,
            name: mapping.decompressorCellType
        )
        let compactorID = StableLogicID.make(
            kind: "dft-scan-compactor",
            path: module.name,
            name: mapping.compactorCellType
        )
        for helperID in [decompressorID, compactorID]
        where module.cells.contains(where: { $0.id == helperID || $0.instanceName == helperID }) {
            throw DFTGateLevelScanTransformError.compressionCellConflict(helperID)
        }
        var netIndexByID = Dictionary(
            uniqueKeysWithValues: module.nets.indices.map { (module.nets[$0].id, $0) }
        )
        var netIDByName = Dictionary(
            uniqueKeysWithValues: module.nets.map { ($0.name, $0.id) }
        )

        let decompressorPins = try makeDecompressorPins(
            configuration: configuration,
            mapping: mapping,
            helperID: decompressorID,
            chainInputNetIDs: chainInputNetIDs,
            module: &module,
            netIndexByID: &netIndexByID,
            netIDByName: &netIDByName
        )
        module.cells.append(GateCell(
            id: decompressorID,
            type: mapping.decompressorCellType,
            instanceName: decompressorID,
            pins: decompressorPins
        ))

        let compactorPins = try makeCompactorPins(
            configuration: configuration,
            mapping: mapping,
            helperID: compactorID,
            chainOutputNetIDs: chainOutputNetIDs,
            module: &module,
            netIndexByID: &netIndexByID,
            netIDByName: &netIDByName
        )
        module.cells.append(GateCell(
            id: compactorID,
            type: mapping.compactorCellType,
            instanceName: compactorID,
            pins: compactorPins
        ))
        return [decompressorID, compactorID]
    }

    private func makeDecompressorPins(
        configuration: DFTCompressionConfiguration,
        mapping: DFTScanCompressionCellMapping,
        helperID: String,
        chainInputNetIDs: [String],
        module: inout GateModule,
        netIndexByID: inout [String: Int],
        netIDByName: inout [String: String]
    ) throws -> [GatePin] {
        var pins: [GatePin] = []
        pins.reserveCapacity(
            mapping.decompressorInputPinNames.count
                + mapping.decompressorOutputPinNames.count
        )
        for (index, signalName) in configuration.scanInputSignals.enumerated() {
            let netID = try ensureExternalSignal(
                signalName,
                direction: .input,
                module: &module,
                netIndexByID: &netIndexByID,
                netIDByName: &netIDByName
            )
            let pinID = StableLogicID.make(
                kind: "dft-scan-decompressor-pin",
                path: helperID,
                name: mapping.decompressorInputPinNames[index]
            )
            pins.append(GatePin(
                id: pinID,
                name: mapping.decompressorInputPinNames[index],
                direction: .input,
                netID: netID
            ))
            appendLoad(
                pinID,
                to: netID,
                module: &module,
                netIndexByID: netIndexByID
            )
        }
        for (index, netID) in chainInputNetIDs.enumerated() {
            let pinID = StableLogicID.make(
                kind: "dft-scan-decompressor-pin",
                path: helperID,
                name: mapping.decompressorOutputPinNames[index]
            )
            pins.append(GatePin(
                id: pinID,
                name: mapping.decompressorOutputPinNames[index],
                direction: .output,
                netID: netID
            ))
            appendDriver(
                pinID,
                to: netID,
                module: &module,
                netIndexByID: netIndexByID
            )
        }
        return pins
    }

    private func makeCompactorPins(
        configuration: DFTCompressionConfiguration,
        mapping: DFTScanCompressionCellMapping,
        helperID: String,
        chainOutputNetIDs: [String],
        module: inout GateModule,
        netIndexByID: inout [String: Int],
        netIDByName: inout [String: String]
    ) throws -> [GatePin] {
        var pins: [GatePin] = []
        pins.reserveCapacity(
            mapping.compactorInputPinNames.count
                + mapping.compactorOutputPinNames.count
        )
        for (index, netID) in chainOutputNetIDs.enumerated() {
            let pinID = StableLogicID.make(
                kind: "dft-scan-compactor-pin",
                path: helperID,
                name: mapping.compactorInputPinNames[index]
            )
            pins.append(GatePin(
                id: pinID,
                name: mapping.compactorInputPinNames[index],
                direction: .input,
                netID: netID
            ))
            appendLoad(
                pinID,
                to: netID,
                module: &module,
                netIndexByID: netIndexByID
            )
        }
        for (index, signalName) in configuration.scanOutputSignals.enumerated() {
            let netID = try ensureExternalSignal(
                signalName,
                direction: .output,
                module: &module,
                netIndexByID: &netIndexByID,
                netIDByName: &netIDByName
            )
            let pinID = StableLogicID.make(
                kind: "dft-scan-compactor-pin",
                path: helperID,
                name: mapping.compactorOutputPinNames[index]
            )
            pins.append(GatePin(
                id: pinID,
                name: mapping.compactorOutputPinNames[index],
                direction: .output,
                netID: netID
            ))
            appendDriver(
                pinID,
                to: netID,
                module: &module,
                netIndexByID: netIndexByID
            )
        }
        return pins
    }

    private func validPinNames(_ names: [String]) -> Bool {
        !names.isEmpty
            && names.allSatisfy {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            && Set(names).count == names.count
    }

    private func ensureExternalSignal(
        _ name: String,
        direction: LogicDirection,
        module: inout GateModule,
        netIndexByID: inout [String: Int],
        netIDByName: inout [String: String]
    ) throws -> String {
        let portID: String
        if let port = module.ports.first(where: { $0.name == name }) {
            guard port.direction == direction else {
                throw DFTGateLevelScanTransformError.controlPortConflict(name: name)
            }
            portID = port.id
        } else {
            portID = StableLogicID.make(kind: "dft-port", path: module.name, name: name)
            module.ports.append(RTLPort(
                id: portID,
                name: name,
                direction: direction,
                dataType: .logic
            ))
        }

        let netID: String
        if let existingID = netIDByName[name] {
            netID = existingID
        } else {
            netID = StableLogicID.make(
                kind: "dft-net",
                path: "\(module.name).\(name)",
                name: name
            )
            guard netIndexByID[netID] == nil else {
                throw DFTGateLevelScanTransformError.generatedNetConflict(name: name)
            }
            module.nets.append(GateNet(id: netID, name: name))
            netIndexByID[netID] = module.nets.index(before: module.nets.endIndex)
            netIDByName[name] = netID
        }
        if let existingBinding = module.portBindings.first(where: {
            $0.portID == portID
        }), existingBinding.netID != netID {
            throw DFTGateLevelScanTransformError.controlPortConflict(name: name)
        }
        module.portBindings.removeAll { $0.portID == portID }
        module.portBindings.append(GatePortBinding(portID: portID, netID: netID))
        return netID
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

    private func appendDriver(
        _ pinID: String,
        to netID: String,
        module: inout GateModule,
        netIndexByID: [String: Int]
    ) {
        guard let index = netIndexByID[netID] else { return }
        if !module.nets[index].driverPinIDs.contains(pinID) {
            module.nets[index].driverPinIDs.append(pinID)
        }
    }
}
