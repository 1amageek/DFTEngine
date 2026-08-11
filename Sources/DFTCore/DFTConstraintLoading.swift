import TimingCore

public protocol DFTConstraintLoading: Sendable {
    func load(
        _ reference: DFTConstraintReference,
        bindings: [DFTArtifactBinding]
    ) async throws -> [TimingConstraintSet]
}
