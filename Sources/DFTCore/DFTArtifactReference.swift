import CircuiteFoundation

/// Foundation-backed artifact identity used by DFT requests and results.
///
/// Requests should use an `ArtifactLocator` until a file has been materialized;
/// this alias is retained for the current DFT request surface while callers
/// migrate to fully verified `ArtifactReference` values.
public typealias DFTArtifactReference = ArtifactReference

public extension ArtifactReference {
    /// Returns the stable Foundation artifact identity as a string.
    var artifactID: String? {
        id.rawValue
    }

    /// Returns the normalized digest for compatibility with DFT validators.
    var sha256: String? {
        digest.algorithm == .sha256 ? digest.hexadecimalValue : nil
    }
}
