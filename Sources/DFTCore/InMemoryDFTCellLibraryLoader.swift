public struct InMemoryDFTCellLibraryLoader: DFTCellLibraryLoading {
    public let manifest: DFTCellLibraryManifest

    public init(manifest: DFTCellLibraryManifest) {
        self.manifest = manifest
    }

    public func load(_ reference: DFTCellLibraryReference) throws -> DFTCellLibraryManifest {
        try DFTCellLibraryManifestCodec.validate(manifest)
        let actualDigest = try DFTCellLibraryManifestCodec.digest(manifest)
        guard actualDigest == reference.manifestDigest else {
            throw DFTCellLibraryError.manifestDigestMismatch(
                expected: reference.manifestDigest,
                actual: actualDigest
            )
        }
        guard manifest.processID == reference.processID else {
            throw DFTCellLibraryError.referenceMismatch(
                field: "processID",
                expected: reference.processID,
                actual: manifest.processID
            )
        }
        guard manifest.version == reference.version else {
            throw DFTCellLibraryError.referenceMismatch(
                field: "version",
                expected: reference.version,
                actual: manifest.version
            )
        }
        return manifest
    }
}
