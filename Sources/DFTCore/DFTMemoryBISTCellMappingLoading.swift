public protocol DFTMemoryBISTCellMappingLoading: Sendable {
    func load(
        _ mapping: DFTMemoryBISTCellMapping
    ) throws -> DFTMemoryBISTCellMappingManifest
}
