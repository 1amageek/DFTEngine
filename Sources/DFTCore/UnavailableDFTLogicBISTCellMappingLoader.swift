public struct UnavailableDFTLogicBISTCellMappingLoader: DFTLogicBISTCellMappingLoading {
    public init() {}

    public func load(
        _ mapping: DFTLogicBISTCellMapping,
        binding: DFTArtifactBinding
    ) async throws -> DFTLogicBISTCellMappingManifest {
        _ = mapping
        _ = binding
        throw DFTLogicBISTCellMappingError.loaderUnavailable
    }
}
