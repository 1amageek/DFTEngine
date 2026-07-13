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
        guard result.metadata.engineID == runner.descriptor.engineID else {
            throw DFTExternalToolError.descriptorMismatch(
                expected: runner.descriptor.engineID,
                actual: result.metadata.engineID
            )
        }
        guard result.metadata.implementationID == runner.descriptor.implementationID else {
            throw DFTExternalToolError.implementationMismatch(
                expected: runner.descriptor.implementationID,
                actual: result.metadata.implementationID
            )
        }
        guard result.metadata.implementationVersion == runner.descriptor.implementationVersion else {
            throw DFTExternalToolError.implementationVersionMismatch(
                expected: runner.descriptor.implementationVersion,
                actual: result.metadata.implementationVersion
            )
        }
        guard result.metadata.startedAt.timeIntervalSinceReferenceDate.isFinite,
              result.metadata.completedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw DFTExternalToolError.invalidExecutionMetadata(
                "execution timestamps must be finite"
            )
        }
        guard result.metadata.completedAt >= result.metadata.startedAt else {
            throw DFTExternalToolError.invalidExecutionMetadata("completedAt precedes startedAt")
        }
        for artifact in result.artifacts {
            do {
                _ = try DFTFoundationEvidence.artifactReference(from: artifact)
            } catch {
                throw DFTExternalToolError.invalidArtifactReference(
                    path: artifact.path,
                    message: error.localizedDescription
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
            diagnostics: result.diagnostics,
            artifacts: result.artifacts + [responseReference, stdoutReference, stderrReference],
            metadata: result.metadata,
            payload: result.payload
        )
    }
}
