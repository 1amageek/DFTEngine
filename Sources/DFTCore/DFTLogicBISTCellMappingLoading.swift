public protocol DFTLogicBISTCellMappingLoading: Sendable {
    func load(
        _ mapping: DFTLogicBISTCellMapping
    ) throws -> DFTLogicBISTCellMappingManifest
}
