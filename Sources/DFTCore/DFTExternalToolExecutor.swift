import Foundation
import CircuiteFoundation

public struct DFTExternalToolExecutor: Sendable {
    public let runner: any DFTExternalToolRunning
    public let artifactStore: (any DFTArtifactStoring)?

    public init(
        runner: any DFTExternalToolRunning,
        artifactStore: (any DFTArtifactStoring)? = nil
    ) {
        self.runner = runner
        self.artifactStore = artifactStore
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
        let output: DFTExternalToolOutput
        if let outputProvidingRunner = runner as? any DFTExternalToolOutputProviding {
            output = try await outputProvidingRunner.runWithOutput(requestData: requestData)
        } else {
            output = DFTExternalToolOutput(
                standardOutput: try await runner.run(requestData: requestData),
                standardError: Data(),
                exitCode: 0
            )
        }
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
        guard result.provenance.producer.identifier == runner.descriptor.engineID else {
            throw DFTExternalToolError.descriptorMismatch(
                expected: runner.descriptor.engineID,
                actual: result.provenance.producer.identifier
            )
        }
        guard result.provenance.producer.build == runner.descriptor.implementationID else {
            throw DFTExternalToolError.implementationMismatch(
                expected: runner.descriptor.implementationID,
                actual: result.provenance.producer.build ?? ""
            )
        }
        guard result.provenance.producer.version == runner.descriptor.implementationVersion else {
            throw DFTExternalToolError.implementationVersionMismatch(
                expected: runner.descriptor.implementationVersion,
                actual: result.provenance.producer.version
            )
        }
        for artifact in result.artifacts {
            guard artifact.byteCount > 0 else {
                throw DFTExternalToolError.invalidArtifactReference(
                    path: artifact.path,
                    message: "Artifact byte count must be greater than zero."
                )
            }
        }
        guard let artifactStore else {
            return result
        }
        let responseReference = try await artifactStore.store(
            DFTArtifactContent(
                artifactID: "dft-external-result",
                fileName: "external-result-result.json",
                kind: .report,
                format: .json,
                data: responseData
            ),
            runID: request.runID
        )
        let stdoutReference = try await artifactStore.store(
            DFTArtifactContent(
                artifactID: "dft-external-stdout",
                fileName: "external-stdout.raw",
                kind: .report,
                format: .raw,
                data: output.standardOutput
            ),
            runID: request.runID
        )
        let stderrReference = try await artifactStore.store(
            DFTArtifactContent(
                artifactID: "dft-external-stderr",
                fileName: "external-stderr.raw",
                kind: .report,
                format: .raw,
                data: output.standardError
            ),
            runID: request.runID
        )
        return DFTResult(
            schemaVersion: result.schemaVersion,
            runID: result.runID,
            status: result.status,
            diagnostics: result.dftDiagnostics,
            artifacts: result.artifacts + [responseReference, stdoutReference, stderrReference],
            provenance: result.provenance,
            evidenceID: result.evidence.id,
            payload: result.payload
        )
    }
}
