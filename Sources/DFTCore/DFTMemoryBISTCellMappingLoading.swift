public protocol DFTMemoryBISTCellMappingLoading: Sendable {
    func load(
        _ mapping: DFTMemoryBISTCellMapping,
        binding: DFTArtifactBinding
    ) async throws -> DFTMemoryBISTCellMappingManifest
}
