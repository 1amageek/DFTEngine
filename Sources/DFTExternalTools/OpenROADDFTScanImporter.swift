import CircuiteFoundation
import DFTCore
import Foundation
import LogicIR

public struct OpenROADDFTScanImporter: OpenROADDFTScanImportProviding {
    public let artifactReader: any DFTArtifactReading
    public let artifactStore: any DFTArtifactStoring

    public init(
        artifactReader: any DFTArtifactReading,
        artifactStore: any DFTArtifactStoring
    ) {
        self.artifactReader = artifactReader
        self.artifactStore = artifactStore
    }

    public func importScan(
        _ request: OpenROADDFTScanImportRequest
    ) async throws -> OpenROADDFTScanImportResult {
        try validate(request)
        let inputs = [
            request.sourceNetlistArtifact,
            request.transformedNetlistArtifact,
            request.scanDEFArtifact,
            request.cellLibraryArtifact,
            request.executionEvidenceArtifact,
        ]
        let data = try await load(inputs)
        let sourceSnapshot = try snapshot(
            data[0],
            name: "source",
            topModule: request.topModule
        )
        let transformedSnapshot = try snapshot(
            data[1],
            name: "transformed",
            topModule: request.topModule
        )
        let cellLibrary: DFTCellLibraryManifest
        do {
            cellLibrary = try DFTCellLibraryManifestCodec.decode(data[3])
            try DFTCellLibraryManifestCodec.validate(cellLibrary)
        } catch {
            throw OpenROADDFTScanImportError.cellLibraryInvalid(
                error.localizedDescription
            )
        }
        let chains = try OpenROADScanDEFParser().parse(data[2])
        let implementation = try makeImplementation(
            request: request,
            sourceSnapshot: sourceSnapshot,
            transformedSnapshot: transformedSnapshot,
            chains: chains,
            cellLibrary: cellLibrary
        )
        let issues = DFTScanImplementationValidator()
            .validationIssues(in: implementation)
        guard issues.isEmpty else {
            throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                issues.map { "\($0.code): \($0.message)" }
                    .joined(separator: "; ")
            )
        }
        return try await persist(
            request: request,
            inputs: inputs,
            sourceSnapshot: sourceSnapshot,
            transformedSnapshot: transformedSnapshot,
            implementation: implementation,
            cellLibrary: cellLibrary
        )
    }

    private func validate(_ request: OpenROADDFTScanImportRequest) throws {
        guard request.schemaVersion
                == OpenROADDFTScanImportRequest.currentSchemaVersion,
              !request.runID.isEmpty,
              isIdentifier(request.architectureName),
              isIdentifier(request.topModule),
              isIdentifier(request.scanEnableSignal),
              isIdentifier(request.testModeSignal),
              request.scanEnableSignal != request.testModeSignal else {
            throw OpenROADDFTScanImportError.invalidRequest(
                "schema, run, architecture, top, and distinct control signals are required"
            )
        }
        let descriptor = request.producer
        guard descriptor.engineID == "dft.scan-insertion",
              !descriptor.implementationID.isEmpty,
              !descriptor.implementationVersion.isEmpty,
              isSHA256(descriptor.binaryDigest) else {
            throw OpenROADDFTScanImportError.invalidRequest(
                "producer must identify a digest-bound DFT scan-insertion implementation"
            )
        }
    }

    private func load(_ references: [ArtifactReference]) async throws -> [Data] {
        var result: [Data] = []
        result.reserveCapacity(references.count)
        for reference in references {
            let data = try await artifactReader.data(for: reference)
            let digest = try SHA256ContentDigester().digest(data: data)
            guard UInt64(data.count) == reference.byteCount,
                  digest == reference.digest else {
                throw OpenROADDFTScanImportError.artifactIntegrityMismatch(
                    path: reference.path
                )
            }
            result.append(data)
        }
        return result
    }

    private func snapshot(
        _ data: Data,
        name: String,
        topModule: String
    ) throws -> LogicDesignSnapshot {
        guard let source = String(data: data, encoding: .utf8) else {
            throw OpenROADDFTScanImportError.inputTextInvalid(
                name: "\(name) netlist"
            )
        }
        let parsed = GateNetlistParser().parse(
            source,
            path: "\(name)-netlist.v",
            topDesignName: topModule
        )
        guard parsed.isValid, let gate = parsed.design else {
            throw OpenROADDFTScanImportError.gateNetlistInvalid(
                name: name,
                diagnostics: parsed.diagnostics.map(\.message)
            )
        }
        return try LogicDesignSnapshotCodec.finalized(
            LogicDesignSnapshot(
                rtl: RTLDesign(topModuleName: topModule),
                gate: gate
            )
        )
    }

    private func makeImplementation(
        request: OpenROADDFTScanImportRequest,
        sourceSnapshot: LogicDesignSnapshot,
        transformedSnapshot: LogicDesignSnapshot,
        chains: [OpenROADScanDEFChain],
        cellLibrary: DFTCellLibraryManifest
    ) throws -> DFTScanImplementation {
        guard let sourceDigest = sourceSnapshot.designDigest,
              let transformedDigest = transformedSnapshot.designDigest,
              let sourceModule = sourceSnapshot.gate?.modules.first(
                where: { $0.name == request.topModule }
              ),
              let module = transformedSnapshot.gate?.modules.first(
                where: { $0.name == request.topModule }
              ) else {
            throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                "canonical source or transformed design identity is missing"
            )
        }
        let groupedCells = Dictionary(grouping: module.cells, by: \.instanceName)
        guard groupedCells.values.allSatisfy({ $0.count == 1 }) else {
            throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                "transformed netlist instance names must be unique"
            )
        }
        let cellsByName = groupedCells.compactMapValues(\.first)
        let groupedSourceCells = Dictionary(
            grouping: sourceModule.cells,
            by: \.instanceName
        )
        guard groupedSourceCells.values.allSatisfy({ $0.count == 1 }) else {
            throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                "source netlist instance names must be unique"
            )
        }
        let sourceCellsByName = groupedSourceCells.compactMapValues(\.first)
        let bindingsByFunctionalType = Dictionary(
            uniqueKeysWithValues: cellLibrary.bindings.map {
                ($0.functionalCellType, $0)
            }
        )
        let expectedScanInstances = Set(
            sourceModule.cells.compactMap { cell in
                bindingsByFunctionalType[cell.type] == nil
                    ? nil
                    : cell.instanceName
            }
        )
        let scanCellTypes = Set(cellLibrary.bindings.map(\.scanCellType))
        let transformedScanInstances = Set(
            module.cells.compactMap { cell in
                scanCellTypes.contains(cell.type) ? cell.instanceName : nil
            }
        )
        let scanEnableNetID = try topLevelNetID(
            for: request.scanEnableSignal,
            in: module
        )
        let testModeNetID = try topLevelNetID(
            for: request.testModeSignal,
            in: module
        )
        let realizedChains = try chains.map { chain in
            let elements = try chain.elements.enumerated().map {
                index,
                element -> DFTScanElementBinding in
                guard let cell = cellsByName[element.instanceName] else {
                    throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                        "ScanDEF instance \(element.instanceName) is absent from the transformed netlist"
                    )
                }
                guard let sourceCell = sourceCellsByName[
                    element.instanceName
                ] else {
                    throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                        "ScanDEF instance \(element.instanceName) is absent from the source netlist"
                    )
                }
                let binding = try binding(
                    for: sourceCell.type,
                    transformedCellType: cell.type,
                    bindingsByFunctionalType: bindingsByFunctionalType
                )
                guard element.scanInPinName == binding.scanInPinName,
                      element.scanOutPinName == binding.outputPinName else {
                    throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                        "ScanDEF access pins for \(element.instanceName) do not match the process binding"
                    )
                }
                let clockPins = cell.pins.filter {
                    binding.clockPinNames.contains($0.name)
                }
                guard clockPins.count == 1, let clockPin = clockPins.first else {
                    throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                        "scan cell \(element.instanceName) has an ambiguous clock binding"
                    )
                }
                let scanEnablePin = try pin(
                    binding.scanEnablePinName,
                    in: cell
                )
                guard scanEnablePin.netID == scanEnableNetID else {
                    throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                        "scan cell \(element.instanceName) is not controlled by \(request.scanEnableSignal)"
                    )
                }
                let testModePinName = binding.testModePinName
                let testModePin = try testModePinName.map {
                    try pin($0, in: cell)
                }
                if let testModePin, testModePin.netID != testModeNetID {
                    throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                        "scan cell \(element.instanceName) is not controlled by \(request.testModeSignal)"
                    )
                }
                return DFTScanElementBinding(
                    position: index,
                    cellID: cell.id,
                    instanceName: cell.instanceName,
                    cellType: cell.type,
                    dataPinName: binding.dataPinName,
                    dataNetID: try requiredNetID(
                        try pin(binding.dataPinName, in: cell),
                        instanceName: cell.instanceName
                    ),
                    outputPinName: binding.outputPinName,
                    outputNetID: try requiredNetID(
                        try pin(binding.outputPinName, in: cell),
                        instanceName: cell.instanceName
                    ),
                    clockPinName: clockPin.name,
                    clockNetID: try requiredNetID(
                        clockPin,
                        instanceName: cell.instanceName
                    ),
                    scanInPinName: binding.scanInPinName,
                    scanInNetID: try requiredNetID(
                        try pin(binding.scanInPinName, in: cell),
                        instanceName: cell.instanceName
                    ),
                    scanEnablePinName: binding.scanEnablePinName,
                    scanEnableNetID: scanEnableNetID,
                    testModePinName: testModePinName,
                    testModeNetID: testModePin == nil ? nil : testModeNetID
                )
            }
            let expectedInputNetID = try topLevelNetID(
                for: chain.startSignal,
                in: module
            )
            let expectedOutputNetID = try topLevelNetID(
                for: chain.stopSignal,
                in: module
            )
            guard let first = elements.first, let last = elements.last,
                  first.scanInNetID == expectedInputNetID,
                  last.outputNetID == expectedOutputNetID else {
                throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                    "chain \(chain.chainID) boundaries do not match its top-level pins"
                )
            }
            return DFTRealizedScanChain(
                chainID: chain.chainID,
                domainID: chain.domainID,
                scanInSignal: chain.startSignal,
                scanInNetID: first.scanInNetID,
                scanOutSignal: chain.stopSignal,
                scanOutNetID: last.outputNetID,
                elements: elements
            )
        }
        let realizedInstanceNames = realizedChains.flatMap(\.elements)
            .map(\.instanceName)
        guard Set(realizedInstanceNames).count == realizedInstanceNames.count,
              Set(realizedInstanceNames) == expectedScanInstances,
              transformedScanInstances == expectedScanInstances else {
            throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                "source scan candidates, transformed scan cells, and ScanDEF elements must identify the same instances exactly once"
            )
        }
        return DFTScanImplementation(
            architectureName: request.architectureName,
            sourceDesignDigest: sourceDigest,
            transformedDesignDigest: transformedDigest,
            scanEnableSignal: request.scanEnableSignal,
            scanEnableNetID: scanEnableNetID,
            testModeSignal: request.testModeSignal,
            testModeNetID: testModeNetID,
            chains: realizedChains
        )
    }

    private func binding(
        for functionalCellType: String,
        transformedCellType: String,
        bindingsByFunctionalType: [String: DFTCellLibraryBinding]
    ) throws -> DFTCellLibraryBinding {
        guard let binding = bindingsByFunctionalType[
            functionalCellType
        ] else {
            throw OpenROADDFTScanImportError.functionalCellBindingMissing(
                cellType: functionalCellType
            )
        }
        guard binding.scanCellType == transformedCellType else {
            throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                "source cell type \(functionalCellType) must map to \(binding.scanCellType), not \(transformedCellType)"
            )
        }
        return binding
    }

    private func pin(_ name: String, in cell: GateCell) throws -> GatePin {
        let matches = cell.pins.filter { $0.name == name }
        guard matches.count == 1, let pin = matches.first else {
            throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                "cell \(cell.instanceName) does not have exactly one \(name) pin"
            )
        }
        return pin
    }

    private func requiredNetID(
        _ pin: GatePin,
        instanceName: String
    ) throws -> String {
        guard let netID = pin.netID, !netID.isEmpty else {
            throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                "cell \(instanceName) pin \(pin.name) is disconnected"
            )
        }
        return netID
    }

    private func topLevelNetID(
        for signal: String,
        in module: GateModule
    ) throws -> String {
        let ports = module.ports.filter { $0.name == signal }
        guard ports.count == 1, let port = ports.first else {
            throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                "top-level signal \(signal) does not resolve to exactly one port"
            )
        }
        let bindings = module.portBindings.filter { $0.portID == port.id }
        guard bindings.count == 1, let binding = bindings.first,
              module.nets.contains(where: { $0.id == binding.netID }) else {
            throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                "top-level signal \(signal) does not resolve to exactly one bound net"
            )
        }
        return binding.netID
    }

    private func persist(
        request: OpenROADDFTScanImportRequest,
        inputs: [ArtifactReference],
        sourceSnapshot: LogicDesignSnapshot,
        transformedSnapshot: LogicDesignSnapshot,
        implementation: DFTScanImplementation,
        cellLibrary: DFTCellLibraryManifest
    ) async throws -> OpenROADDFTScanImportResult {
        guard let sourceDigest = sourceSnapshot.designDigest,
              let transformedDigest = transformedSnapshot.designDigest else {
            throw OpenROADDFTScanImportError.scanConnectivityInvalid(
                "finalized design digests are missing"
            )
        }
        let evidence = OpenROADDFTScanImportEvidence(
            producer: request.producer,
            processID: cellLibrary.processID,
            pdkDigest: cellLibrary.pdkDigest,
            inputs: inputs,
            sourceDesignDigest: sourceDigest,
            transformedDesignDigest: transformedDigest,
            scanImplementationDigest: try DFTDeterministicHasher()
                .digest(implementation)
        )
        let contents: [DFTArtifactContent]
        do {
            contents = [
                DFTArtifactContent(
                    artifactID: "dft-openroad-source-design",
                    fileName: "openroad-source-design.json",
                    kind: .netlist,
                    format: .json,
                    data: try LogicDesignSnapshotCodec.encode(sourceSnapshot)
                ),
                DFTArtifactContent(
                    artifactID: "dft-openroad-transformed-design",
                    fileName: "openroad-transformed-design.json",
                    kind: .netlist,
                    format: .json,
                    data: try LogicDesignSnapshotCodec.encode(
                        transformedSnapshot
                    )
                ),
                DFTArtifactContent(
                    artifactID: "dft-openroad-scan-implementation",
                    fileName: "openroad-scan-implementation.json",
                    kind: .report,
                    format: .json,
                    data: try DFTArtifactJSONEncoder().encode(implementation)
                ),
                DFTArtifactContent(
                    artifactID: "dft-openroad-scan-import-evidence",
                    fileName: "openroad-scan-import-evidence.json",
                    kind: .evidence,
                    format: .json,
                    data: try DFTArtifactJSONEncoder().encode(evidence)
                ),
            ]
        } catch {
            throw OpenROADDFTScanImportError.artifactPersistenceFailed(
                error.localizedDescription
            )
        }
        let artifacts: [ArtifactReference]
        do {
            artifacts = try await artifactStore.storeBatch(
                contents,
                runID: request.runID
            )
        } catch {
            throw OpenROADDFTScanImportError.artifactPersistenceFailed(
                error.localizedDescription
            )
        }
        let groupedArtifacts = Dictionary(
            grouping: artifacts,
            by: { $0.id.rawValue }
        )
        guard groupedArtifacts.values.allSatisfy({ $0.count == 1 }) else {
            throw OpenROADDFTScanImportError.artifactPersistenceFailed(
                "stored artifact identities are duplicated"
            )
        }
        let byID = groupedArtifacts.compactMapValues(\.first)
        guard let sourceArtifact = byID["dft-openroad-source-design"],
              let transformedArtifact = byID[
                "dft-openroad-transformed-design"
              ],
              let implementationArtifact = byID[
                "dft-openroad-scan-implementation"
              ] else {
            throw OpenROADDFTScanImportError.artifactPersistenceFailed(
                "stored artifact identities are incomplete"
            )
        }
        return OpenROADDFTScanImportResult(
            runID: request.runID,
            producer: request.producer,
            processID: cellLibrary.processID,
            pdkDigest: cellLibrary.pdkDigest,
            inputs: inputs,
            sourceDesign: LogicDesignReference(
                artifact: sourceArtifact,
                topDesignName: request.topModule,
                designDigest: sourceDigest
            ),
            transformedDesign: LogicDesignReference(
                artifact: transformedArtifact,
                topDesignName: request.topModule,
                designDigest: transformedDigest
            ),
            scanImplementation: DFTScanImplementationReference(
                artifact: implementationArtifact,
                transformedDesignDigest: transformedDigest
            ),
            artifacts: artifacts
        )
    }

    private func isIdentifier(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z_][A-Za-z0-9_$]*$"#,
            options: .regularExpression
        ) != nil
    }

    private func isSHA256(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9a-fA-F]{64}$"#,
            options: .regularExpression
        ) != nil
    }
}

private struct OpenROADDFTScanImportEvidence:
    Sendable,
    Hashable,
    Codable
{
    let producer: DFTExternalToolDescriptor
    let processID: String
    let pdkDigest: String
    let inputs: [ArtifactReference]
    let sourceDesignDigest: String
    let transformedDesignDigest: String
    let scanImplementationDigest: String
}
