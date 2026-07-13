import Foundation

public struct DFTExecutionSupport: Sendable {
    public static let implementationVersion = "1.0.0"

    public init() {}

    public static func metadata(
        engineID: String,
        implementationID: String,
        startedAt: Date,
        completedAt: Date,
        seed: UInt64? = nil
    ) -> DFTExecutionMetadata {
        DFTExecutionMetadata(
            engineID: engineID,
            implementationID: implementationID,
            implementationVersion: implementationVersion,
            startedAt: startedAt,
            completedAt: completedAt,
            seed: seed
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
        artifacts: [DFTArtifactReference] = [],
        payload: DFTPayload,
        startedAt: Date,
        seed: UInt64? = nil
    ) -> DFTResult {
        DFTResult(
            schemaVersion: DFTRequest.currentSchemaVersion,
            runID: request.runID,
            status: status,
            diagnostics: diagnostics,
            artifacts: artifacts,
            metadata: metadata(
                engineID: engineID,
                implementationID: implementationID,
                startedAt: startedAt,
                completedAt: Date(),
                seed: seed
            ),
            payload: payload
        )
    }
}
