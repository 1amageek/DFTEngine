@_exported import CircuiteFoundation
import Foundation

/// Foundation projection of a DFT execution.
///
/// DFT evidence view exposing the domain result through Foundation contracts.
public struct DFTFoundationEvidence: Sendable, Hashable, Codable, ArtifactProducing,
    EvidenceProviding, DiagnosticReporting
{
    public let evidence: EvidenceManifest
    public let diagnostics: [DesignDiagnostic]

    public var artifacts: [ArtifactReference] { evidence.artifacts }

    public init(
        result: DFTResult,
        provenance: ExecutionProvenance
    ) throws {
        self.evidence = EvidenceManifest(provenance: provenance, artifacts: result.artifacts)
        self.diagnostics = try result.diagnostics.map(Self.makeDiagnostic)
    }

    /// Returns a verified Foundation reference for execution provenance.
    public static func artifactReference(
        from reference: DFTArtifactReference
    ) throws -> ArtifactReference {
        reference
    }

    private static func makeDiagnostic(
        _ diagnostic: DFTDiagnostic
    ) throws -> DesignDiagnostic {
        let code: DiagnosticCode
        do {
            code = try DiagnosticCode(rawValue: diagnostic.code)
        } catch {
            throw DFTFoundationBoundaryError.invalidDiagnosticCode(diagnostic.code)
        }
        let severity: DiagnosticSeverity
        switch diagnostic.severity {
        case .info:
            severity = .information
        case .warning:
            severity = .warning
        case .error:
            severity = .error
        }
        let detail = diagnostic.entity.map { "entity: \($0)" }
        return DesignDiagnostic(
            code: code,
            severity: severity,
            summary: diagnostic.message,
            detail: detail,
            suggestedActions: diagnostic.suggestedActions.map {
                SuggestedAction(code: $0, summary: $0)
            }
        )
    }
}
