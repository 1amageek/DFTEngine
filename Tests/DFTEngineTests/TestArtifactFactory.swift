import CircuiteFoundation
import Foundation

/// Builds immutable Foundation artifacts for test fixtures.
func testArtifact(
    artifactID: String? = nil,
    path: String,
    kind: ArtifactKind,
    format: ArtifactFormat,
    sha256: String? = nil,
    byteCount: Int64? = nil,
    role: ArtifactRole = .legacyUnspecified
) -> ArtifactReference {
    do {
        let location = try ArtifactLocation(workspaceRelativePath: path)
        let locator = ArtifactLocator(
            location: location,
            role: role,
            kind: kind,
            format: format
        )
        let digest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: sha256 ?? String(repeating: "0", count: 64)
        )
        let id = try artifactID.map { try ArtifactID(rawValue: $0) }
        return ArtifactReference(
            id: id,
            locator: locator,
            digest: digest,
            byteCount: UInt64(max(0, byteCount ?? 0))
        )
    } catch {
        preconditionFailure("Invalid test artifact fixture: \(error)")
    }
}
