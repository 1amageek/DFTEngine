import Foundation
import CircuiteFoundation

/// DFT-owned execution result.
public struct DFTResult: Sendable, Hashable, Codable, ArtifactProducing,
    EvidenceProviding, DiagnosticReporting
{
    public var schemaVersion: Int
    public var runID: String
    public var status: DFTExecutionStatus
    public var dftDiagnostics: [DFTDiagnostic]
    public var artifacts: [ArtifactReference] {
        didSet {
            evidence = EvidenceManifest(
                id: evidence.id,
                provenance: provenance,
                artifacts: artifacts
            )
        }
    }
    public var provenance: ExecutionProvenance {
        didSet {
            evidence = EvidenceManifest(
                id: evidence.id,
                provenance: provenance,
                artifacts: artifacts
            )
        }
    }
    public var payload: DFTPayload
    public private(set) var evidence: EvidenceManifest

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case status
        case dftDiagnostics
        case artifacts
        case provenance
        case payload
        case evidence
    }

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
        self.dftDiagnostics = diagnostics
        self.artifacts = artifacts
        self.provenance = provenance
        self.payload = payload
        self.evidence = EvidenceManifest(provenance: provenance, artifacts: artifacts)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        runID = try container.decode(String.self, forKey: .runID)
        status = try container.decode(DFTExecutionStatus.self, forKey: .status)
        dftDiagnostics = try container.decode([DFTDiagnostic].self, forKey: .dftDiagnostics)
        artifacts = try container.decode([ArtifactReference].self, forKey: .artifacts)
        provenance = try container.decode(ExecutionProvenance.self, forKey: .provenance)
        payload = try container.decode(DFTPayload.self, forKey: .payload)
        evidence = try container.decode(EvidenceManifest.self, forKey: .evidence)
        guard evidence.provenance == provenance, evidence.artifacts == artifacts else {
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
            do {
                code = try DiagnosticCode(rawValue: "dft.invalid-diagnostic-code")
            } catch {
                preconditionFailure("The built-in DFT diagnostic code must be valid.")
            }
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
