public protocol DFTScanImplementationLoading: Sendable {
    func load(
        _ reference: DFTScanImplementationReference
    ) async throws -> DFTScanImplementation
}
