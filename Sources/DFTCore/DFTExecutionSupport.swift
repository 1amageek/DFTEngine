import Foundation
import CircuiteFoundation

public struct DFTExecutionSupport: Sendable {
    public static let implementationVersion = "1.0.0"

    public init() {}

    public static func provenance(
        engineID: String,
        implementationID: String,
        implementationVersion: String = Self.implementationVersion,
        inputs: [ArtifactReference] = [],
        startedAt: Date,
        completedAt: Date,
        seed: UInt64? = nil
    ) throws -> ExecutionProvenance {
        try ExecutionProvenance(
            producer: ProducerIdentity(
                kind: .engine,
                identifier: implementationID,
                version: implementationVersion,
                build: engineID
            ),
            inputs: inputs,
            invocation: ExecutionInvocation.inProcess(
                entryPoint: "DFTExecutionSupport.result"
            ),
            randomSeed: seed,
            startedAt: startedAt,
            completedAt: completedAt
        )
    }

    public static func diagnostics(
        for issues: [DFTRequestValidationIssue]
    ) -> [DFTDiagnostic] {
        issues.map { issue in
            DFTDiagnostic(
                severity: .error,
                code: issue.code,
                message: issue.message,
                entity: issue.entity,
                suggestedActions: issue.suggestedActions
            )
        }
    }

    public static func result(
        request: DFTRequest,
        engineID: String,
        implementationID: String,
        status: DFTExecutionStatus,
        diagnostics: [DFTDiagnostic],
        artifacts: [ArtifactReference] = [],
        payload: DFTPayload,
        startedAt: Date,
        seed: UInt64? = nil
    ) throws -> DFTResult {
        let result = DFTResult(
            schemaVersion: DFTRequest.currentSchemaVersion,
            runID: request.runID,
            status: status,
            diagnostics: diagnostics,
            artifacts: artifacts,
            provenance: try provenance(
                engineID: engineID,
                implementationID: implementationID,
                inputs: request.executionInputArtifacts,
                startedAt: startedAt,
                completedAt: Date(),
                seed: seed
            ),
            payload: payload
        )
        try DFTResultValidator().validate(result, for: request)
        return result
    }
}
