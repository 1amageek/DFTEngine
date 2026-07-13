@_exported import CircuiteFoundation
import Foundation
import XcircuitePackage

/// Foundation projection of a DFT execution.
///
/// DFT keeps its domain-specific request, payload and legacy result envelope,
/// while this value exposes the shared artifact, evidence and diagnostic
/// contracts to flow coordinators and Agent clients.
public struct DFTFoundationEvidence: Sendable, Hashable, Codable, ArtifactProducing,
    EvidenceProviding, DiagnosticReporting
{
    public let evidence: EvidenceManifest
    public let diagnostics: [DesignDiagnostic]

    public var artifacts: [ArtifactReference] { evidence.artifacts }

    public init(
        result: XcircuiteEngineResultEnvelope<DFTPayload>,
        provenance: ExecutionProvenance
    ) throws {
        self.evidence = EvidenceManifest(
            provenance: provenance,
            artifacts: try result.artifacts.map(Self.makeArtifactReference)
        )
        self.diagnostics = try result.diagnostics.map(Self.makeDiagnostic)
    }

    /// Converts a verified legacy reference for use in execution provenance.
    public static func artifactReference(
        from reference: XcircuiteFileReference
    ) throws -> ArtifactReference {
        try makeArtifactReference(reference)
    }

    private static func makeArtifactReference(
        _ reference: XcircuiteFileReference
    ) throws -> ArtifactReference {
        guard let artifactID = reference.artifactID, !artifactID.isEmpty else {
            throw DFTFoundationBoundaryError.missingArtifactID(reference.path)
        }
        let foundationID: ArtifactID
        do {
            foundationID = try ArtifactID(rawValue: artifactID)
        } catch {
            throw DFTFoundationBoundaryError.invalidArtifactID(
                path: reference.path,
                reason: error.localizedDescription
            )
        }
        guard let sha256 = reference.sha256, !sha256.isEmpty else {
            throw DFTFoundationBoundaryError.missingDigest(reference.path)
        }
        let digest: ContentDigest
        do {
            digest = try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: sha256
            )
        } catch {
            throw DFTFoundationBoundaryError.invalidDigest(reference.path)
        }
        guard let byteCount = reference.byteCount else {
            throw DFTFoundationBoundaryError.missingByteCount(reference.path)
        }
        guard byteCount >= 0 else {
            throw DFTFoundationBoundaryError.invalidByteCount(reference.path)
        }

        let location: ArtifactLocation
        do {
            if reference.path.hasPrefix("/") {
                location = try ArtifactLocation(
                    fileURL: URL(fileURLWithPath: reference.path)
                )
            } else {
                location = try ArtifactLocation(
                    workspaceRelativePath: reference.path
                )
            }
        } catch {
            throw DFTFoundationBoundaryError.invalidArtifactLocation(reference.path)
        }

        let kind: ArtifactKind
        do {
            kind = try ArtifactKind(rawValue: reference.kind.rawValue)
        } catch {
            throw DFTFoundationBoundaryError.invalidArtifactKind(
                path: reference.path,
                reason: error.localizedDescription
            )
        }
        let format: ArtifactFormat
        do {
            format = try makeArtifactFormat(reference.format)
        } catch {
            throw DFTFoundationBoundaryError.invalidArtifactFormat(
                path: reference.path,
                reason: error.localizedDescription
            )
        }

        return ArtifactReference(
            id: foundationID,
            locator: ArtifactLocator(
                location: location,
                kind: kind,
                format: format
            ),
            digest: digest,
            byteCount: UInt64(byteCount)
        )
    }

    private static func makeArtifactFormat(
        _ format: XcircuiteFileFormat
    ) throws -> ArtifactFormat {
        switch format {
        case .spice:
            return .spice
        case .systemVerilog:
            return .systemVerilog
        case .verilog:
            return .verilog
        case .oasis:
            return .oasis
        case .gdsii:
            return .gdsii
        case .lef:
            return .lef
        case .def:
            return .def
        case .spef:
            return .spef
        case .dspf:
            return .dspf
        case .liberty:
            return .liberty
        case .sdc:
            return try ArtifactFormat(rawValue: "sdc")
        case .sdf:
            return .sdf
        case .upf:
            return try ArtifactFormat(rawValue: "upf")
        case .cpf:
            return try ArtifactFormat(rawValue: "cpf")
        case .vcd:
            return .vcd
        case .fst:
            return try ArtifactFormat(rawValue: "fst")
        case .stil:
            return try ArtifactFormat(rawValue: "stil")
        case .wgl:
            return try ArtifactFormat(rawValue: "wgl")
        case .json:
            return .json
        case .raw:
            return try ArtifactFormat(rawValue: "raw")
        case .csv:
            return try ArtifactFormat(rawValue: "csv")
        case .text:
            return try ArtifactFormat(rawValue: "text")
        case .unknown:
            return try ArtifactFormat(rawValue: "unknown")
        }
    }

    private static func makeDiagnostic(
        _ diagnostic: XcircuiteEngineDiagnostic
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
