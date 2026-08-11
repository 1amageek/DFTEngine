public protocol DFTCellLibraryLoading: Sendable {
    func load(
        _ reference: DFTCellLibraryReference,
        binding: DFTArtifactBinding
    ) async throws -> DFTCellLibraryManifest
}
