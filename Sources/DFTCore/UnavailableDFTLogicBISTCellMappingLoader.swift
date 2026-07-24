public struct UnavailableDFTLogicBISTCellMappingLoader: DFTLogicBISTCellMappingLoading {
    public init() {}

    public func load(
        _ mapping: DFTLogicBISTCellMapping
    ) throws -> DFTLogicBISTCellMappingManifest {
        _ = mapping
        throw DFTLogicBISTCellMappingError.loaderUnavailable
    }
}
