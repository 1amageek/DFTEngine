import CircuiteFoundation
import CircuiteFoundationFoundation
import DFTCore
import Foundation

/// Builds immutable Foundation artifacts for test fixtures.
func testArtifact(
    artifactID: String? = nil,
    path: String,
    kind: ArtifactKind,
    format: ArtifactFormat,
    sha256: String? = nil,
    byteCount: Int64? = nil,
    role: ArtifactRole
) -> ArtifactReference {
    do {
        let digest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: sha256 ?? String(repeating: "0", count: 64)
        )
        return try ArtifactReference(
            digest: digest,
            byteCount: UInt64(max(0, byteCount ?? 0)),
            descriptor: ArtifactDescriptor(
                role: role,
                kind: kind,
                format: format
            )
        )
    } catch {
        preconditionFailure("Invalid test artifact fixture: \(error)")
    }
}

func testArtifactBinding(
    artifactID: String,
    path: String,
    kind: ArtifactKind,
    format: ArtifactFormat,
    sha256: String? = nil,
    byteCount: Int64? = nil,
    role: ArtifactRole
) -> DFTArtifactBinding {
    do {
        let reference = testArtifact(
            artifactID: artifactID,
            path: path,
            kind: kind,
            format: format,
            sha256: sha256,
            byteCount: byteCount,
            role: role
        )
        return try DFTArtifactBinding(
            logicalID: artifactID,
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: try ArtifactRootID(rawValue: "dft-project"),
                relativePath: try ArtifactRelativePath(
                    segments: path.split(separator: "/").map(String.init)
                )
            )
        )
    } catch {
        preconditionFailure("Invalid test artifact binding fixture: \(error)")
    }
}

func testArtifactBinding(
    logicalID: String,
    reference: ArtifactReference,
    path: String
) -> DFTArtifactBinding {
    do {
        return try DFTArtifactBinding(
            logicalID: logicalID,
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: try ArtifactRootID(rawValue: "dft-project"),
                relativePath: try ArtifactRelativePath(
                    segments: path.split(separator: "/").map(String.init)
                )
            )
        )
    } catch {
        preconditionFailure("Invalid existing artifact binding fixture: \(error)")
    }
}

func testArtifactLocator(
    path: String,
    reference: ArtifactReference
) -> ArtifactLocator {
    do {
        return ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: reference.descriptor.role,
            kind: reference.descriptor.kind,
            format: reference.descriptor.format
        )
    } catch {
        preconditionFailure("Invalid test artifact locator fixture: \(error)")
    }
}
