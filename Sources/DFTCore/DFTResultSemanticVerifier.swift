import CircuiteFoundation
import Foundation
import LogicIR

public struct DFTResultSemanticVerifier: Sendable {
    public init() {}

    public func validate(
        _ result: DFTResult,
        for request: DFTRequest,
        reading artifacts: any DFTArtifactReading
    ) async throws {
        try DFTResultValidator().validate(result, for: request)
        guard result.status == .completed else {
            throw DFTResultSemanticValidationError.resultNotCompleted
        }
        switch request.operation {
        case .scanInsertion:
            try await validateScanInsertion(result, request: request, reading: artifacts)
        case .atpg:
            return
        case .bist:
            try await validateBIST(result, request: request, reading: artifacts)
        }
    }

    private func validateScanInsertion(
        _ result: DFTResult,
        request: DFTRequest,
        reading artifacts: any DFTArtifactReading
    ) async throws {
        guard let transformedDesign = result.payload.transformedDesign,
              let plan = result.payload.scanPlan,
              let architecture = request.scanArchitecture,
              let policy = request.insertionPolicy else {
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
