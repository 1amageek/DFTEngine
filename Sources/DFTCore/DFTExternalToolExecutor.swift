import Foundation
import CircuiteFoundation

public struct DFTExternalToolExecutor: Sendable {
    public let runner: any DFTExternalToolOutputProviding
    public let artifactStore: (any DFTArtifactStoring)?
    public let artifactReader: (any DFTArtifactReading)?
    public let semanticVerifier: DFTResultSemanticVerifier

    public init(
        runner: any DFTExternalToolOutputProviding,
        artifactStore: (any DFTArtifactStoring)? = nil,
        artifactReader: (any DFTArtifactReading)? = nil,
        semanticVerifier: DFTResultSemanticVerifier = DFTResultSemanticVerifier()
    ) {
        self.runner = runner
        self.artifactStore = artifactStore
        self.artifactReader = artifactReader
        self.semanticVerifier = semanticVerifier
    }

    public func execute(
        _ request: DFTRequest
    ) async throws -> DFTResult {
        let requestData: Data
        do {
            requestData = try DFTArtifactJSONEncoder().encode(request)
        } catch {
            throw DFTExternalToolError.requestEncodingFailed(error.localizedDescription)
        }
        let output = try await runner.runWithOutput(requestData: requestData)
        guard output.exitCode == 0 else {
            throw DFTExternalToolError.nonZeroExit(
                implementationID: runner.descriptor.implementationID,
                exitCode: output.exitCode,
                standardError: String(decoding: output.standardError, as: UTF8.self)
            )
        }
        let responseData = output.standardOutput
        let result: DFTResult
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            result = try decoder.decode(
                DFTResult.self,
                from: responseData
            )
        } catch {
            throw DFTExternalToolError.responseDecodingFailed(error.localizedDescription)
        }
        guard result.schemaVersion == DFTRequest.currentSchemaVersion else {
            throw DFTExternalToolError.schemaVersionMismatch(result.schemaVersion)
        }
        guard result.runID == request.runID else {
            throw DFTExternalToolError.runIDMismatch(
                expected: request.runID,
                actual: result.runID
            )
        }
        guard result.provenance.inputs == request.executionInputArtifacts else {
            throw DFTExternalToolError.provenanceInputMismatch
        }
        guard result.provenance.producer.identifier == runner.descriptor.implementationID else {
            throw DFTExternalToolError.implementationMismatch(
                expected: runner.descriptor.implementationID,
                actual: result.provenance.producer.identifier
            )
        }
        guard result.provenance.producer.build?.caseInsensitiveCompare(
            runner.descriptor.binaryDigest
        ) == .orderedSame else {
            throw DFTExternalToolError.descriptorMismatch(
                expected: runner.descriptor.binaryDigest,
                actual: result.provenance.producer.build ?? ""
            )
        }
        guard result.provenance.producer.version == runner.descriptor.implementationVersion else {
            throw DFTExternalToolError.implementationVersionMismatch(
                expected: runner.descriptor.implementationVersion,
                actual: result.provenance.producer.version
            )
        }
        try DFTResultValidator().validate(result, for: request)
        if result.status == .completed {
            guard let artifactReader else {
                throw DFTExternalToolError.artifactReaderUnavailable
            }
            try await semanticVerifier.validate(
                result,
                for: request,
                reading: artifactReader
            )
        }
        guard let artifactStore else {
            return result
        }
        let persistedBindings = try await artifactStore.storeBatch(
            [
            DFTArtifactContent(
                artifactID: "dft-external-result",
                fileName: "external-result-result.json",
                kind: .report,
                format: .json,
                data: responseData
            ),
            DFTArtifactContent(
                artifactID: "dft-external-stdout",
                fileName: "external-stdout.raw",
                kind: .report,
                format: .raw,
                data: output.standardOutput
            ),
            DFTArtifactContent(
                artifactID: "dft-external-stderr",
                fileName: "external-stderr.raw",
                kind: .report,
                format: .raw,
                data: output.standardError
            )
            ],
            runID: request.runID
        )
        let persistedResult = try DFTResult(
            schemaVersion: result.schemaVersion,
            runID: result.runID,
            status: result.status,
            diagnostics: result.dftDiagnostics,
            artifactBindings: result.artifactBindings + persistedBindings,
            provenance: result.provenance,
            payload: result.payload
        )
        try DFTResultValidator().validate(persistedResult, for: request)
        return persistedResult
    }
}
