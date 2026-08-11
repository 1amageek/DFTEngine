public protocol DFTScanImplementationLoading: Sendable {
    func load(
        _ reference: DFTScanImplementationReference,
        binding: DFTArtifactBinding
    ) async throws -> DFTScanImplementation
}
