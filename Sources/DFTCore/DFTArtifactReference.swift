import CircuiteFoundation

/// Foundation-backed artifact identity used by DFT requests and results.
///
/// Requests should use an `ArtifactLocator` until a file has been materialized;
/// this alias gives the DFT domain a concise name while preserving the exact
/// canonical `ArtifactReference` representation.
public typealias DFTArtifactReference = ArtifactReference

public extension ArtifactReference {
    /// Returns the stable Foundation artifact identity as a string.
    var artifactID: String? {
        id.rawValue
    }

    /// Returns the normalized SHA-256 digest consumed by DFT validators.
    var sha256: String? {
        digest.algorithm == .sha256 ? digest.hexadecimalValue : nil
    }
}
