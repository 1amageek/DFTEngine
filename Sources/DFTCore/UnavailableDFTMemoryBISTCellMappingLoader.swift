public struct UnavailableDFTMemoryBISTCellMappingLoader: DFTMemoryBISTCellMappingLoading {
    public init() {}

    public func load(
        _ mapping: DFTMemoryBISTCellMapping
    ) throws -> DFTMemoryBISTCellMappingManifest {
        _ = mapping
        throw DFTMemoryBISTCellMappingError.loaderUnavailable
    }
}
