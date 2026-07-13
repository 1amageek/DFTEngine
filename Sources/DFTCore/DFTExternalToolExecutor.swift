import Foundation
import CircuiteFoundation
import XcircuitePackage

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
    ) async throws -> XcircuiteEngineResultEnvelope<DFTPayload> {
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
        let envelope: XcircuiteEngineResultEnvelope<DFTPayload>
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            envelope = try decoder.decode(
                XcircuiteEngineResultEnvelope<DFTPayload>.self,
                from: responseData
            )
        } catch {
            throw DFTExternalToolError.responseDecodingFailed(error.localizedDescription)
        }
        guard envelope.schemaVersion == DFTRequest.currentSchemaVersion else {
            throw DFTExternalToolError.schemaVersionMismatch(envelope.schemaVersion)
        }
        guard envelope.runID == request.runID else {
            throw DFTExternalToolError.runIDMismatch(
                expected: request.runID,
                actual: envelope.runID
            )
        }
        guard envelope.metadata.engineID == runner.descriptor.engineID else {
            throw DFTExternalToolError.descriptorMismatch(
                expected: runner.descriptor.engineID,
                actual: envelope.metadata.engineID
            )
        }
        guard envelope.metadata.implementationID == runner.descriptor.implementationID else {
            throw DFTExternalToolError.implementationMismatch(
                expected: runner.descriptor.implementationID,
                actual: envelope.metadata.implementationID
            )
        }
        guard envelope.metadata.implementationVersion == runner.descriptor.implementationVersion else {
            throw DFTExternalToolError.implementationVersionMismatch(
                expected: runner.descriptor.implementationVersion,
                actual: envelope.metadata.implementationVersion
            )
        }
        guard envelope.metadata.startedAt.timeIntervalSinceReferenceDate.isFinite,
              envelope.metadata.completedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw DFTExternalToolError.invalidExecutionMetadata(
                "execution timestamps must be finite"
            )
        }
        guard envelope.metadata.completedAt >= envelope.metadata.startedAt else {
            throw DFTExternalToolError.invalidExecutionMetadata("completedAt precedes startedAt")
        }
        for artifact in envelope.artifacts {
            guard artifact.producedByRunID == nil || artifact.producedByRunID == request.runID else {
                throw DFTExternalToolError.invalidArtifactReference(
                    path: artifact.path,
                    message: "producedByRunID must match the request run ID"
                )
            }
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
            return envelope
        }
        let responseReference = try await artifactStore.store(
            DFTArtifactContent(
                artifactID: "dft-external-result-envelope",
                fileName: "external-result-envelope.json",
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
        return XcircuiteEngineResultEnvelope(
            schemaVersion: envelope.schemaVersion,
            runID: envelope.runID,
            status: envelope.status,
            diagnostics: envelope.diagnostics,
            artifacts: envelope.artifacts + [responseReference, stdoutReference, stderrReference],
            metadata: envelope.metadata,
            payload: envelope.payload
        )
    }
}
