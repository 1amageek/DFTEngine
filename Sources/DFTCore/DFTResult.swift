import Foundation
import CircuiteFoundation
import CircuiteFoundationCrypto

/// DFT-owned execution result.
public struct DFTResult: Sendable, Hashable, Codable, ArtifactProducing,
    EvidenceProviding, DiagnosticReporting
{
    public let schemaVersion: Int
    public let runID: String
    public let status: DFTExecutionStatus
    public let dftDiagnostics: [DFTDiagnostic]
    public let artifactBindings: [DFTArtifactBinding]
    public var artifacts: [ArtifactReference] { artifactBindings.map(\.reference) }
    public let provenance: ExecutionProvenance
    public let payload: DFTPayload
    public let evidence: EvidenceManifest

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case status
        case dftDiagnostics
        case artifactBindings
        case provenance
        case payload
        case evidence
    }

    public init(
        schemaVersion: Int,
        runID: String,
        status: DFTExecutionStatus,
        diagnostics: [DFTDiagnostic] = [],
        artifactBindings: [DFTArtifactBinding] = [],
        provenance: ExecutionProvenance,
        payload: DFTPayload
    ) throws {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.dftDiagnostics = diagnostics
        self.artifactBindings = artifactBindings
        self.provenance = provenance
        self.payload = payload
        self.evidence = try EvidenceManifest.contentAddressed(
            provenance: provenance,
            artifacts: artifactBindings.map(\.reference),
            digester: SHA256ContentDigester()
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        runID = try container.decode(String.self, forKey: .runID)
        status = try container.decode(DFTExecutionStatus.self, forKey: .status)
        dftDiagnostics = try container.decode([DFTDiagnostic].self, forKey: .dftDiagnostics)
        artifactBindings = try container.decode([DFTArtifactBinding].self, forKey: .artifactBindings)
        provenance = try container.decode(ExecutionProvenance.self, forKey: .provenance)
        payload = try container.decode(DFTPayload.self, forKey: .payload)
        evidence = try container.decode(EvidenceManifest.self, forKey: .evidence)
        guard evidence.provenance == provenance,
              evidence.artifacts == artifactBindings.map(\.reference) else {
            throw DecodingError.dataCorruptedError(
                forKey: .evidence,
                in: container,
                debugDescription: "DFT evidence does not match result provenance and artifacts."
            )
        }
    }

    public var diagnostics: [DesignDiagnostic] {
        dftDiagnostics.map(Self.designDiagnostic)
    }

    private static func designDiagnostic(_ diagnostic: DFTDiagnostic) -> DesignDiagnostic {
        let code: DiagnosticCode
        do {
            code = try DiagnosticCode(rawValue: diagnostic.code)
        } catch {
            code = .trusted("dft.invalid-diagnostic-code")
        }
        let severity: DiagnosticSeverity
        switch diagnostic.severity {
        case .info: severity = .information
        case .warning: severity = .warning
        case .error: severity = .error
        }
        let detail = [
            diagnostic.entity.map { "entity: \($0)" },
            code.rawValue == "dft.invalid-diagnostic-code"
                ? "originalCode: \(diagnostic.code)"
                : nil,
        ].compactMap { $0 }.joined(separator: "; ")
        return DesignDiagnostic(
            code: code,
            severity: severity,
            summary: diagnostic.message,
            detail: detail.isEmpty ? nil : detail,
            suggestedActions: diagnostic.suggestedActions.map {
                SuggestedAction(code: $0, summary: $0)
            }
        )
    }
}
