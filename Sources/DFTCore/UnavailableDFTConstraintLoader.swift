import TimingCore

public struct UnavailableDFTConstraintLoader: DFTConstraintLoading {
    public init() {}

    public func load(
        _ reference: DFTConstraintReference,
        bindings: [DFTArtifactBinding]
    ) async throws -> [TimingConstraintSet] {
        _ = reference
        _ = bindings
        throw DFTConstraintError.loaderUnavailable
    }
}
