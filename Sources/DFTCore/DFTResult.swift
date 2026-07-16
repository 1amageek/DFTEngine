import Foundation
import CircuiteFoundation

/// DFT-owned execution result.
public struct DFTResult: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var runID: String
    public var status: DFTExecutionStatus
    public var diagnostics: [DFTDiagnostic]
    public var artifacts: [ArtifactReference]
    public var provenance: ExecutionProvenance
    public var payload: DFTPayload

    public init(
        schemaVersion: Int,
        runID: String,
        status: DFTExecutionStatus,
        diagnostics: [DFTDiagnostic] = [],
        artifacts: [ArtifactReference] = [],
        provenance: ExecutionProvenance,
        payload: DFTPayload
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.diagnostics = diagnostics
        self.artifacts = artifacts
        self.provenance = provenance
        self.payload = payload
    }
}
