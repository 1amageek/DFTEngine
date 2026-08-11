public protocol DFTLogicBISTCellMappingLoading: Sendable {
    func load(
        _ mapping: DFTLogicBISTCellMapping,
        binding: DFTArtifactBinding
    ) async throws -> DFTLogicBISTCellMappingManifest
}
