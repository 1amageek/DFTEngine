public protocol DFTCellLibraryLoading: Sendable {
    func load(_ reference: DFTCellLibraryReference) throws -> DFTCellLibraryManifest
}
