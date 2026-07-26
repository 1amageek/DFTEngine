public protocol DFTScanPatternReplayProviding: Sendable {
    func replay(
        _ request: DFTScanPatternReplayRequest
    ) async throws -> DFTScanPatternReplayResult
}
