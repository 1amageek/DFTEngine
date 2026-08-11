public struct UnavailableDFTMemoryBISTCellMappingLoader: DFTMemoryBISTCellMappingLoading {
    public init() {}

    public func load(
        _ mapping: DFTMemoryBISTCellMapping,
        binding: DFTArtifactBinding
    ) async throws -> DFTMemoryBISTCellMappingManifest {
        _ = mapping
        _ = binding
        throw DFTMemoryBISTCellMappingError.loaderUnavailable
    }
}
