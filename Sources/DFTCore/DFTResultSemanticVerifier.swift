import CircuiteFoundation
import Foundation
import LogicIR
import PDKCore

public struct DFTResultSemanticVerifier: Sendable {
    public let atpgVerifier: any DFTATPGResultSemanticVerifying

    public init(
        atpgVerifier: any DFTATPGResultSemanticVerifying =
            UnavailableDFTATPGResultSemanticVerifier()
    ) {
        self.atpgVerifier = atpgVerifier
    }

    public func validate(
        _ result: DFTResult,
        for request: DFTRequest,
        reading artifacts: any DFTArtifactReading
    ) async throws {
        try DFTResultValidator().validate(result, for: request)
        guard result.status == .completed else {
            throw DFTResultSemanticValidationError.resultNotCompleted
        }
        try await validatePDK(request.pdk, reading: artifacts)
        switch request.operation {
        case .scanInsertion:
            try await validateScanInsertion(result, request: request, reading: artifacts)
        case .atpg:
            let design = try await loadSnapshot(
                request.design,
                requireEmbeddedDigest: false,
                reading: artifacts
            )
            let scanImplementation: DFTScanImplementation?
            if let reference = request.scanImplementation {
                scanImplementation = try await loadScanImplementation(
                    reference,
                    reading: artifacts
                )
                try await validateScanExecutionPlanArtifact(
                    result,
                    reading: artifacts
                )
            } else {
                scanImplementation = nil
            }
            try await atpgVerifier.validate(
                result,
                for: request,
                design: design,
                scanImplementation: scanImplementation
            )
        case .bist:
            try await validateBIST(result, request: request, reading: artifacts)
        }
    }

    private func loadScanImplementation(
        _ reference: DFTScanImplementationReference,
        reading artifacts: any DFTArtifactReading
    ) async throws -> DFTScanImplementation {
        do {
            return try await VerifiedDFTScanImplementationLoader(
                artifactReader: artifacts
            ).load(reference)
        } catch {
            throw DFTResultSemanticValidationError.artifactDecodeFailed(
                "scan implementation: \(error.localizedDescription)"
            )
        }
    }

    private func validateScanExecutionPlanArtifact(
        _ result: DFTResult,
        reading artifacts: any DFTArtifactReading
    ) async throws {
        guard let payloadPlan = result.payload.scanPatternExecutionPlan,
              let reference = result.artifacts.first(where: {
                  $0.id.rawValue == "dft-scan-pattern-execution-plan"
              }) else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "scan execution-plan artifact is missing"
            )
        }
        let data = try await verifiedData(for: reference, reading: artifacts)
        let retainedPlan: DFTScanPatternExecutionPlan
        do {
            retainedPlan = try JSONDecoder().decode(
                DFTScanPatternExecutionPlan.self,
                from: data
            )
        } catch {
            throw DFTResultSemanticValidationError.artifactDecodeFailed(
                "scan execution plan: \(error.localizedDescription)"
            )
        }
        guard retainedPlan == payloadPlan else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "scan execution-plan payload does not match retained bytes"
            )
        }
    }

    private func validatePDK(
        _ reference: PDKReference,
        reading artifacts: any DFTArtifactReading
    ) async throws {
        let data = try await verifiedData(for: reference.manifest, reading: artifacts)
        let manifest: PDKManifest
        do {
            manifest = try PDKManifestCodec.decode(data: data)
        } catch {
            throw DFTResultSemanticValidationError.artifactDecodeFailed(
                "PDK manifest: \(error.localizedDescription)"
            )
        }
        guard manifest.processID == reference.processID,
              manifest.version == reference.version else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "PDK manifest process identity does not match the DFT request"
            )
        }
        let validation = PDKManifestValidator().validate(manifest)
        guard validation.isValid else {
            let codes = validation.findings
                .filter { $0.severity == .blocker || $0.severity == .error }
                .map(\.code)
                .sorted()
                .joined(separator: ", ")
            throw DFTResultSemanticValidationError.semanticMismatch(
                "PDK manifest semantic validation failed: \(codes)"
            )
        }
    }

    private func validateScanInsertion(
        _ result: DFTResult,
        request: DFTRequest,
        reading artifacts: any DFTArtifactReading
    ) async throws {
        guard let transformedDesign = result.payload.transformedDesign,
              let plan = result.payload.scanPlan,
              let implementation = result.payload.scanImplementation,
              let architecture = request.scanArchitecture,
              let policy = request.insertionPolicy,
              let libraryReference = request.cellLibrary else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "scan insertion outputs are incomplete"
            )
        }
        let source = try await loadSnapshot(
            request.design,
            requireEmbeddedDigest: false,
            reading: artifacts
        )
        let transformed = try await loadSnapshot(
            transformedDesign,
            requireEmbeddedDigest: true,
            reading: artifacts
        )
        guard let implementationReference = result.artifacts.first(where: {
            $0.id.rawValue == "dft-scan-implementation"
        }) else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "scan implementation artifact is missing"
            )
        }
        let implementationData = try await verifiedData(
            for: implementationReference,
            reading: artifacts
        )
        let retainedImplementation: DFTScanImplementation
        do {
            retainedImplementation = try JSONDecoder().decode(
                DFTScanImplementation.self,
                from: implementationData
            )
        } catch {
            throw DFTResultSemanticValidationError.artifactDecodeFailed(
                "scan implementation: \(error.localizedDescription)"
            )
        }
        guard retainedImplementation == implementation else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "scan implementation payload does not match retained bytes"
            )
        }
        try validatePreservedDesignEnvelope(
            source: source,
            transformed: transformed
        )
        let libraryData = try await verifiedData(
            for: libraryReference.artifact,
            reading: artifacts
        )
        let library: DFTCellLibraryManifest
        do {
            library = try DFTCellLibraryManifestCodec.decode(libraryData)
            try DFTCellLibraryManifestCodec.validate(library)
        } catch {
            throw DFTResultSemanticValidationError.artifactDecodeFailed(
                "DFT cell library: \(error.localizedDescription)"
            )
        }
        guard try DFTCellLibraryManifestCodec.digest(library)
                == libraryReference.manifestDigest,
              library.processID == request.pdk.processID,
              library.version == request.pdk.version,
              library.pdkDigest == request.pdk.digest else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "scan cell-library evidence is not bound to the requested PDK"
            )
        }
        guard source.designDigest != transformed.designDigest else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "scan insertion retained an unchanged design"
            )
        }
        let module = try topModule(in: transformed)
        let scanCells = module.cells.filter { $0.type == policy.scanCellName }
        guard scanCells.count == plan.totalEstimatedElementCount else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "transformed scan-cell count does not match the scan plan"
            )
        }
        var expectedAddedPorts: [String: LogicDirection] = [
            architecture.scanEnableSignal: .input,
            architecture.testModeSignal: .input,
        ]
        for chain in plan.chains {
            expectedAddedPorts[chain.scanInSignal] = .input
            expectedAddedPorts[chain.scanOutSignal] = .output
        }
        try validatePreservedModuleInterface(
            source: try topModule(in: source),
            transformed: module,
            expectedAddedPorts: expectedAddedPorts
        )
        let requiredPorts = Set(
            [architecture.scanEnableSignal, architecture.testModeSignal]
                + plan.chains.flatMap { [$0.scanInSignal, $0.scanOutSignal] }
        )
        let portsByName = module.ports.reduce(into: [String: RTLPort]()) {
            $0[$1.name] = $1
        }
        let bindingsByPortID = module.portBindings.reduce(
            into: [String: GatePortBinding]()
        ) {
            $0[$1.portID] = $1
        }
        guard requiredPorts.allSatisfy({ name in
            guard let port = portsByName[name],
                  let binding = bindingsByPortID[port.id] else {
                return false
            }
            return module.nets.contains(where: { $0.id == binding.netID })
        }) else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "scan control or chain ports are not canonically bound"
            )
        }
        try validateScanConnectivity(
            source: try topModule(in: source),
            transformed: module,
            plan: plan,
            architecture: architecture,
            policy: policy,
            library: library
        )
        try validateScanImplementation(
            implementation,
            transformed: module
        )
    }

    private func validateScanImplementation(
        _ implementation: DFTScanImplementation,
        transformed: GateModule
    ) throws {
        let cellsByID = Dictionary(
            uniqueKeysWithValues: transformed.cells.map { ($0.id, $0) }
        )
        let netIDs = Set(transformed.nets.map(\.id))
        for chain in implementation.chains {
            for element in chain.elements {
                guard let cell = cellsByID[element.cellID],
                      cell.instanceName == element.instanceName,
                      cell.type == element.cellType,
                      pinNet(element.dataPinName, in: cell)
                        == element.dataNetID,
                      pinNet(element.outputPinName, in: cell)
                        == element.outputNetID,
                      pinNet(element.clockPinName, in: cell)
                        == element.clockNetID,
                      pinNet(element.scanInPinName, in: cell)
                        == element.scanInNetID,
                      pinNet(element.scanEnablePinName, in: cell)
                        == element.scanEnableNetID,
                      element.testModePinName == nil
                        || pinNet(element.testModePinName!, in: cell)
                            == element.testModeNetID,
                      netIDs.contains(element.dataNetID),
                      netIDs.contains(element.outputNetID),
                      netIDs.contains(element.clockNetID),
                      netIDs.contains(element.scanInNetID) else {
                    throw DFTResultSemanticValidationError.semanticMismatch(
                        "scan implementation is detached from transformed cell \(element.cellID)"
                    )
                }
            }
        }
    }

    private func validateScanConnectivity(
        source: GateModule,
        transformed: GateModule,
        plan: DFTScanPlan,
        architecture: DFTScanArchitecture,
        policy: DFTScanInsertionPolicy,
        library: DFTCellLibraryManifest
    ) throws {
        let bindingByType = Dictionary(
            uniqueKeysWithValues: library.bindings.map {
                ($0.functionalCellType, $0)
            }
        )
        let transformedByID = Dictionary(
            uniqueKeysWithValues: transformed.cells.map { ($0.id, $0) }
        )
        guard source.cells.count == transformed.cells.count else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "scan insertion added or removed functional cells"
            )
        }
        let sourceNetsByID = Dictionary(
            uniqueKeysWithValues: source.nets.map { ($0.id, $0) }
        )
        var cellsByDomain: [String: [GateCell]] = [:]
        for sourceCell in source.cells {
            guard let transformedCell = transformedByID[sourceCell.id] else {
                throw DFTResultSemanticValidationError.semanticMismatch(
                    "scan insertion removed cell \(sourceCell.id)"
                )
            }
            guard let binding = bindingByType[sourceCell.type] else {
                guard transformedCell == sourceCell else {
                    throw DFTResultSemanticValidationError.semanticMismatch(
                        "scan insertion modified non-scan cell \(sourceCell.id)"
                    )
                }
                continue
            }
            guard transformedCell.type == binding.scanCellType,
                  transformedCell.instanceName == sourceCell.instanceName,
                  transformedCell.parameters == sourceCell.parameters else {
                throw DFTResultSemanticValidationError.semanticMismatch(
                    "scan replacement for \(sourceCell.id) violates its cell-library binding"
                )
            }
            let allowedPinNames = Set(
                sourceCell.pins.map(\.name)
                    + [binding.scanInPinName, binding.scanEnablePinName]
                    + (binding.testModePinName.map { [$0] } ?? [])
            )
            guard Set(transformedCell.pins.map(\.name)) == allowedPinNames else {
                throw DFTResultSemanticValidationError.semanticMismatch(
                    "scan replacement for \(sourceCell.id) contains undeclared pins"
                )
            }
            for sourcePin in sourceCell.pins {
                guard transformedCell.pins.contains(sourcePin) else {
                    throw DFTResultSemanticValidationError.semanticMismatch(
                        "scan replacement changed functional pin \(sourcePin.id)"
                    )
                }
            }
            let clockNetIDs = sourceCell.pins.filter { pin in
                binding.clockPinNames.contains {
                    $0.caseInsensitiveCompare(pin.name) == .orderedSame
                }
            }.compactMap(\.netID)
            let clockSignals = Set(clockNetIDs.compactMap {
                sourceNetsByID[$0]?.name
            })
            guard clockSignals.count == 1,
                  let clockSignal = clockSignals.first,
                  let clock = architecture.clocks.first(where: {
                      $0.signalName == clockSignal
                  }),
                  let domain = architecture.domains.first(where: {
                      $0.clockID == clock.id
                  }) else {
                throw DFTResultSemanticValidationError.semanticMismatch(
                    "scan replacement \(sourceCell.id) has no unambiguous clock domain"
                )
            }
            cellsByDomain[domain.id, default: []].append(sourceCell)
        }
        cellsByDomain = cellsByDomain.mapValues {
            $0.sorted { $0.instanceName < $1.instanceName }
        }

        let scanEnableNet = controlNet(
            named: architecture.scanEnableSignal,
            in: transformed
        )
        let testModeNet = controlNet(
            named: architecture.testModeSignal,
            in: transformed
        )
        guard scanEnableNet != nil,
              !policy.requireTestMode || testModeNet != nil else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "scan control nets are not bound"
            )
        }
        for chain in plan.chains {
            let domainCells = cellsByDomain[chain.domainID] ?? []
            let offset = plan.chains
                .filter {
                    $0.domainID == chain.domainID && $0.index < chain.index
                }
                .reduce(0) { $0 + $1.estimatedElementCount }
            guard offset + chain.estimatedElementCount <= domainCells.count else {
                throw DFTResultSemanticValidationError.semanticMismatch(
                    "scan chain \(chain.id) exceeds its domain cell set"
                )
            }
            let chainCells = domainCells[
                offset..<(offset + chain.estimatedElementCount)
            ]
            guard var previousNet = controlNet(
                named: chain.scanInSignal,
                in: transformed
            ) else {
                throw DFTResultSemanticValidationError.semanticMismatch(
                    "scan chain \(chain.id) has no bound input"
                )
            }
            for sourceCell in chainCells {
                guard let binding = bindingByType[sourceCell.type],
                      let transformedCell = transformedByID[sourceCell.id],
                      pinDirection(binding.scanInPinName, in: transformedCell)
                        == .input,
                      pinDirection(binding.scanEnablePinName, in: transformedCell)
                        == .input,
                      binding.testModePinName == nil
                        || pinDirection(
                            binding.testModePinName!,
                            in: transformedCell
                        ) == .input,
                      pinNet(binding.scanInPinName, in: transformedCell)
                        == previousNet,
                      pinNet(binding.scanEnablePinName, in: transformedCell)
                        == scanEnableNet,
                      binding.testModePinName == nil
                        || pinNet(binding.testModePinName!, in: transformedCell)
                            == testModeNet,
                      let outputNet = pinNet(
                          binding.outputPinName,
                          in: transformedCell
                      ) else {
                    throw DFTResultSemanticValidationError.semanticMismatch(
                        "scan chain \(chain.id) is disconnected at \(sourceCell.id)"
                    )
                }
                previousNet = outputNet
            }
            guard controlNet(named: chain.scanOutSignal, in: transformed)
                    == previousNet else {
                throw DFTResultSemanticValidationError.semanticMismatch(
                    "scan chain \(chain.id) output is not bound to its final scan cell"
                )
            }
        }
    }

    private func validateBIST(
        _ result: DFTResult,
        request: DFTRequest,
        reading artifacts: any DFTArtifactReading
    ) async throws {
        guard let transformedDesign = result.payload.transformedDesign,
              let structure = result.payload.bistStructure,
              let configuration = request.bistConfiguration else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "BIST outputs are incomplete"
            )
        }
        let source = try await loadSnapshot(
            request.design,
            requireEmbeddedDigest: false,
            reading: artifacts
        )
        let transformed = try await loadSnapshot(
            transformedDesign,
            requireEmbeddedDigest: true,
            reading: artifacts
        )
        try validatePreservedDesignEnvelope(
            source: source,
            transformed: transformed
        )
        guard source.designDigest != transformed.designDigest else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "BIST retained an unchanged design"
            )
        }
        let module = try topModule(in: transformed)
        let instanceNames = Set(module.cells.map(\.instanceName))
        guard Set(configuration.targetInstances).isSubset(of: instanceNames) else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "BIST target instances are absent from the transformed design"
            )
        }
        if configuration.kind == .memory {
            guard structure.memoryBindings == configuration.memoryBindings,
                  structure.logicCellMapping == nil else {
                throw DFTResultSemanticValidationError.semanticMismatch(
                    "memory-BIST bindings are not retained exactly"
                )
            }
            return
        }
        guard let declaredMapping = configuration.logicCellMapping,
              structure.logicCellMapping == declaredMapping,
              structure.memoryBindings == nil else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "logic-BIST mapping is not retained exactly"
            )
        }
        guard let clockSignal = configuration.clockSignal
                ?? request.scanArchitecture?.clocks.first?.signalName,
              !clockSignal.isEmpty else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "logic-BIST has no reproducible clock signal"
            )
        }
        let mappingData = try await verifiedData(
            for: declaredMapping.artifact,
            reading: artifacts
        )
        let loadedMapping: DFTLogicBISTCellMappingManifest
        do {
            loadedMapping = try JSONDecoder().decode(
                DFTLogicBISTCellMappingManifest.self,
                from: mappingData
            )
        } catch {
            throw DFTResultSemanticValidationError.artifactDecodeFailed(
                error.localizedDescription
            )
        }
        guard loadedMapping == declaredMapping.manifest else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "logic-BIST mapping artifact does not match the executed mapping"
            )
        }
        let requiredCellTypes = Set([
            loadedMapping.controllerCellType,
            loadedMapping.inputMuxCellType,
            loadedMapping.responseCaptureCellType,
            loadedMapping.responseCompactorCellType,
            loadedMapping.signatureRegisterCellType,
        ])
        guard requiredCellTypes.isSubset(of: Set(module.cells.map(\.type))) else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "transformed design does not contain every declared logic-BIST helper-cell type"
            )
        }
        try validateLogicBISTTransform(
            source: try topModule(in: source),
            transformed: module,
            configuration: configuration,
            structure: structure,
            mapping: loadedMapping,
            clockSignal: clockSignal
        )
    }

    private func validateLogicBISTTransform(
        source: GateModule,
        transformed: GateModule,
        configuration: DFTBISTConfiguration,
        structure: DFTBISTStructure,
        mapping: DFTLogicBISTCellMappingManifest,
        clockSignal: String
    ) throws {
        guard let bindings = configuration.targetBindings, !bindings.isEmpty else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "logic-BIST target bindings are missing"
            )
        }
        let prefix = "bist_\(safeIdentifier(configuration.name))"
        let controllerID = "\(prefix)_controller"
        let signatureID = "\(prefix)_signature_register"
        let compactorID = "\(prefix)_response_compactor"
        let sourceByID = Dictionary(uniqueKeysWithValues: source.cells.map { ($0.id, $0) })
        let transformedByID = Dictionary(
            uniqueKeysWithValues: transformed.cells.map { ($0.id, $0) }
        )
        let bindingsByInstance = Dictionary(
            uniqueKeysWithValues: bindings.map { ($0.instanceName, $0) }
        )
        try validatePreservedModuleInterface(
            source: source,
            transformed: transformed,
            expectedAddedPorts: [
                structure.testModeSignal: .input,
                "\(prefix)_done": .output,
                "\(prefix)_signature": .output,
            ]
        )

        for sourceCell in source.cells {
            guard let transformedCell = transformedByID[sourceCell.id],
                  transformedCell.type == sourceCell.type,
                  transformedCell.instanceName == sourceCell.instanceName,
                  transformedCell.parameters == sourceCell.parameters,
                  transformedCell.pins.count == sourceCell.pins.count else {
                throw DFTResultSemanticValidationError.semanticMismatch(
                    "logic-BIST modified or removed functional cell \(sourceCell.id)"
                )
            }
            let rewiredNames = Set(
                bindingsByInstance[sourceCell.instanceName]?.patternInputPinNames
                    ?? []
            )
            guard sourceCell.pins.allSatisfy({ sourcePin in
                guard let transformedPin = transformedCell.pins.first(where: {
                    $0.id == sourcePin.id
                }) else {
                    return false
                }
                let sameContract = transformedPin.name == sourcePin.name
                    && transformedPin.direction == sourcePin.direction
                return sameContract
                    && (rewiredNames.contains(sourcePin.name)
                        || transformedPin.netID == sourcePin.netID)
            }) else {
                throw DFTResultSemanticValidationError.semanticMismatch(
                    "logic-BIST changed an undeclared functional pin on \(sourceCell.id)"
                )
            }
        }

        var expectedGeneratedIDs = Set([controllerID, signatureID, compactorID])
        var captureNetIDs: [String] = []
        for binding in bindings.sorted(by: { $0.instanceName < $1.instanceName }) {
            guard let sourceTarget = source.cells.first(where: {
                $0.instanceName == binding.instanceName
            }),
            let transformedTarget = transformed.cells.first(where: {
                $0.instanceName == binding.instanceName
            }) else {
                throw DFTResultSemanticValidationError.semanticMismatch(
                    "logic-BIST target \(binding.instanceName) is missing"
                )
            }
            for pinName in binding.patternInputPinNames {
                guard let sourcePin = sourceTarget.pins.first(where: {
                    $0.name.caseInsensitiveCompare(pinName) == .orderedSame
                }),
                let transformedPin = transformedTarget.pins.first(where: {
                    $0.id == sourcePin.id
                }),
                let sourceNetID = sourcePin.netID,
                let targetNetID = transformedPin.netID else {
                    throw DFTResultSemanticValidationError.semanticMismatch(
                        "logic-BIST input binding \(binding.instanceName).\(pinName) is invalid"
                    )
                }
                let token = safeIdentifier("\(binding.instanceName)_\(pinName)")
                let muxID = "\(prefix)_\(token)_input_mux"
                expectedGeneratedIDs.insert(muxID)
                guard let mux = transformedByID[muxID],
                      mux.type == mapping.inputMuxCellType,
                      mux.instanceName == muxID,
                      hasExactPins(
                        [
                            "FUNC": .input,
                            "BIST": .input,
                            "TEST_MODE": .input,
                            "Y": .output,
                        ],
                        in: mux
                      ),
                      mux.parameters.isEmpty,
                      pinNet("FUNC", in: mux) == sourceNetID,
                      pinNet("BIST", in: mux) == "\(prefix)_pattern",
                      pinNet("TEST_MODE", in: mux) == controlNet(
                        named: structure.testModeSignal,
                        in: transformed
                      ),
                      pinNet("Y", in: mux) == targetNetID else {
                    throw DFTResultSemanticValidationError.semanticMismatch(
                        "logic-BIST mux \(muxID) is not connected to its functional and test paths"
                    )
                }
            }
            for (captureIndex, pinName) in binding.responseOutputPinNames.enumerated() {
                guard let sourcePin = sourceTarget.pins.first(where: {
                    $0.name.caseInsensitiveCompare(pinName) == .orderedSame
                }),
                let sourceNetID = sourcePin.netID else {
                    throw DFTResultSemanticValidationError.semanticMismatch(
                        "logic-BIST response binding \(binding.instanceName).\(pinName) is invalid"
                    )
                }
                let token = safeIdentifier(
                    "\(binding.instanceName)_\(pinName)_\(captureIndex)"
                )
                let captureID = "\(prefix)_\(token)_capture_cell"
                let captureNetID = "\(prefix)_\(token)_capture"
                expectedGeneratedIDs.insert(captureID)
                captureNetIDs.append(captureNetID)
                guard let capture = transformedByID[captureID],
                      capture.type == mapping.responseCaptureCellType,
                      capture.instanceName == captureID,
                      hasExactPins(
                        ["I": .input, "O": .output],
                        in: capture
                      ),
                      capture.parameters.isEmpty,
                      pinNet("I", in: capture) == sourceNetID,
                      pinNet("O", in: capture) == captureNetID else {
                    throw DFTResultSemanticValidationError.semanticMismatch(
                        "logic-BIST capture cell \(captureID) is not connected to its target response"
                    )
                }
            }
        }
        let actualGeneratedIDs = Set(transformedByID.keys).subtracting(sourceByID.keys)
        guard actualGeneratedIDs == expectedGeneratedIDs else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "logic-BIST generated cell set does not match the declared transform"
            )
        }
        guard let controller = transformedByID[controllerID],
              controller.type == mapping.controllerCellType,
              controller.instanceName == controllerID,
              hasExactPins(
                [
                    "TEST_MODE": .input,
                    "CLK": .input,
                    "PATTERN": .output,
                    "DONE": .output,
                ],
                in: controller
              ),
              Set(controller.parameters.map(\.name))
                == Set([
                    "patternCount",
                    "seed",
                    "prpgPolynomialTaps",
                ]),
              parameter("patternCount", in: controller)
                == .unsignedInteger(UInt64(configuration.patternCount)),
              parameter("seed", in: controller) == .unsignedInteger(structure.seed),
              parameter("prpgPolynomialTaps", in: controller)
                == .integerList(mapping.prpgPolynomialTaps.map(Int64.init)),
              pinNet("TEST_MODE", in: controller) == controlNet(
                named: structure.testModeSignal,
                in: transformed
              ),
              pinNet("CLK", in: controller)
                == netID(named: clockSignal, in: transformed),
              pinNet("PATTERN", in: controller) == "\(prefix)_pattern",
              pinNet("DONE", in: controller) == "\(prefix)_done" else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "logic-BIST controller parameters or output connections are invalid"
            )
        }
        guard let compactor = transformedByID[compactorID],
              compactor.type == mapping.responseCompactorCellType,
              hasExactPins(
                Dictionary(
                    uniqueKeysWithValues:
                        captureNetIDs.indices.map { ("I\($0)", .input) }
                        + [("Y", .output)]
                ),
                in: compactor
              ),
              Set(compactor.parameters.map(\.name))
                == Set(["responseWidth", "misrPolynomialTaps"]),
              parameter("responseWidth", in: compactor)
                == .unsignedInteger(UInt64(captureNetIDs.count)),
              parameter("misrPolynomialTaps", in: compactor)
                == .integerList(mapping.misrPolynomialTaps.map(Int64.init)),
              Set(compactor.pins.filter { $0.direction == .input }.compactMap(\.netID))
                == Set(captureNetIDs),
              pinNet("Y", in: compactor) == "\(prefix)_response" else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "logic-BIST response compactor parameters or connections are invalid"
            )
        }
        guard let signature = transformedByID[signatureID],
              signature.type == mapping.signatureRegisterCellType,
              signature.instanceName == configuration.signatureRegisterName,
              hasExactPins(
                [
                    "DATA": .input,
                    "CLK": .input,
                    "TEST_MODE": .input,
                    "Q": .output,
                ],
                in: signature
              ),
              Set(signature.parameters.map(\.name))
                == Set(["misrPolynomialTaps", "expectedSignature"]),
              parameter("misrPolynomialTaps", in: signature)
                == .integerList(mapping.misrPolynomialTaps.map(Int64.init)),
              parameter("expectedSignature", in: signature)
                == .bitVector(mapping.expectedSignature),
              pinNet("DATA", in: signature) == "\(prefix)_response",
              pinNet("CLK", in: signature) == pinNet("CLK", in: controller),
              pinNet("TEST_MODE", in: signature)
                == pinNet("TEST_MODE", in: controller),
              pinNet("Q", in: signature) == "\(prefix)_signature" else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "logic-BIST signature register parameters or connections are invalid"
            )
        }
        guard controlNet(named: "\(prefix)_done", in: transformed)
                == "\(prefix)_done",
              controlNet(named: "\(prefix)_signature", in: transformed)
                == "\(prefix)_signature" else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "logic-BIST result ports are not bound to controller and signature outputs"
            )
        }
    }

    private func pinNet(_ name: String, in cell: GateCell) -> String? {
        cell.pins.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }?.netID
    }

    private func pinDirection(
        _ name: String,
        in cell: GateCell
    ) -> GatePinDirection? {
        cell.pins.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }?.direction
    }

    private func netID(
        named name: String?,
        in module: GateModule
    ) -> String? {
        guard let name else {
            return nil
        }
        return module.nets.first {
            $0.id == name || $0.name == name
        }?.id
    }

    private func hasExactPins(
        _ expected: [String: GatePinDirection],
        in cell: GateCell
    ) -> Bool {
        guard cell.pins.count == expected.count else {
            return false
        }
        return cell.pins.allSatisfy { pin in
            expected[pin.name] == pin.direction
        }
    }

    private func validatePreservedModuleInterface(
        source: GateModule,
        transformed: GateModule,
        expectedAddedPorts: [String: LogicDirection]
    ) throws {
        let transformedPortsByID = Dictionary(
            uniqueKeysWithValues: transformed.ports.map { ($0.id, $0) }
        )
        guard source.ports.allSatisfy({
            transformedPortsByID[$0.id] == $0
        }) else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "DFT transformation changed a functional top-level port"
            )
        }
        let sourcePortIDs = Set(source.ports.map(\.id))
        let sourcePortNames = Set(source.ports.map(\.name))
        let actualAddedPorts = transformed.ports.filter {
            !sourcePortIDs.contains($0.id)
        }
        let expectedAddedPortNames = Set(expectedAddedPorts.keys)
            .subtracting(sourcePortNames)
        guard Set(actualAddedPorts.map(\.name)) == expectedAddedPortNames,
              actualAddedPorts.allSatisfy({
                  expectedAddedPorts[$0.name] == $0.direction
                      && $0.range == nil
                      && $0.rangeExpression == nil
                      && !$0.isSigned
              }),
              expectedAddedPorts.allSatisfy({ entry in
                  transformed.ports.contains {
                      $0.name == entry.key
                          && $0.direction == entry.value
                          && $0.range == nil
                          && $0.rangeExpression == nil
                          && !$0.isSigned
                  }
              }) else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "DFT transformation added an undeclared top-level port"
            )
        }
        guard source.portBindings.allSatisfy({
            transformed.portBindings.contains($0)
        }) else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "DFT transformation changed a functional port binding"
            )
        }
        let transformedNetsByID = Dictionary(
            uniqueKeysWithValues: transformed.nets.map { ($0.id, $0) }
        )
        guard source.nets.allSatisfy({ sourceNet in
            guard let transformedNet = transformedNetsByID[sourceNet.id] else {
                return false
            }
            return transformedNet.name == sourceNet.name
                && transformedNet.width == sourceNet.width
                && transformedNet.source == sourceNet.source
        }) else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "DFT transformation removed or redefined a functional net"
            )
        }
        let sourceNetIDs = Set(source.nets.map(\.id))
        let referencedNetIDs = Set(
            transformed.portBindings.map(\.netID)
                + transformed.cells.flatMap(\.pins).compactMap(\.netID)
        )
        guard transformed.nets
            .filter({ !sourceNetIDs.contains($0.id) })
            .allSatisfy({ referencedNetIDs.contains($0.id) }) else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "DFT transformation retained an unreferenced generated net"
            )
        }
    }

    private func validatePreservedDesignEnvelope(
        source: LogicDesignSnapshot,
        transformed: LogicDesignSnapshot
    ) throws {
        guard source.rtl == transformed.rtl,
              let sourceGate = source.gate,
              let transformedGate = transformed.gate,
              sourceGate.topModuleName == transformedGate.topModuleName,
              sourceGate.modules.count == transformedGate.modules.count else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "DFT transformation changed RTL or gate-design module identity"
            )
        }
        let transformedModulesByID = Dictionary(
            uniqueKeysWithValues: transformedGate.modules.map {
                ($0.id, $0)
            }
        )
        guard sourceGate.modules.allSatisfy({ sourceModule in
            guard let transformedModule = transformedModulesByID[
                sourceModule.id
            ] else {
                return false
            }
            if sourceModule.name == sourceGate.topModuleName {
                return transformedModule.name == sourceModule.name
            }
            return transformedModule == sourceModule
        }) else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "DFT transformation changed a non-top gate module"
            )
        }
    }

    private func parameter(
        _ name: String,
        in cell: GateCell
    ) -> GateCellParameterValue? {
        cell.parameters.first { $0.name == name }?.value
    }

    private func controlNet(named name: String, in module: GateModule) -> String? {
        guard let port = module.ports.first(where: { $0.name == name }) else {
            return nil
        }
        return module.portBindings.first { $0.portID == port.id }?.netID
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

    private func loadSnapshot(
        _ reference: LogicDesignReference,
        requireEmbeddedDigest: Bool,
        reading artifacts: any DFTArtifactReading
    ) async throws -> LogicDesignSnapshot {
        let data = try await verifiedData(for: reference.artifact, reading: artifacts)
        let snapshot: LogicDesignSnapshot
        do {
            snapshot = try LogicDesignSnapshotCodec.decode(data)
        } catch {
            throw DFTResultSemanticValidationError.artifactDecodeFailed(
                error.localizedDescription
            )
        }
        let digest = try LogicDesignSnapshotCodec.digest(snapshot)
        guard digest == reference.designDigest,
              !requireEmbeddedDigest || snapshot.designDigest == digest else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "LogicDesignReference digest does not match the decoded snapshot"
            )
        }
        guard let gate = snapshot.gate,
              LogicDesignValidator().validate(gate).isValid else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "decoded DFT design is not a valid canonical gate design"
            )
        }
        return snapshot
    }

    private func topModule(
        in snapshot: LogicDesignSnapshot
    ) throws -> GateModule {
        guard let gate = snapshot.gate,
              let module = gate.modules.first(where: {
                  $0.name == gate.topModuleName
              }) else {
            throw DFTResultSemanticValidationError.semanticMismatch(
                "canonical gate design has no top module"
            )
        }
        return module
    }

    private func verifiedData(
        for reference: ArtifactReference,
        reading artifacts: any DFTArtifactReading
    ) async throws -> Data {
        let data = try await artifacts.data(for: reference)
        guard UInt64(data.count) == reference.byteCount,
              try SHA256ContentDigester().digest(data: data) == reference.digest else {
            throw DFTResultSemanticValidationError.artifactIdentityMismatch(
                reference.path
            )
        }
        return data
    }
}
