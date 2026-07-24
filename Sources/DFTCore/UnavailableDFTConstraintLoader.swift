import TimingCore

public struct UnavailableDFTConstraintLoader: DFTConstraintLoading {
    public init() {}

    public func load(
        _ reference: DFTConstraintReference
    ) throws -> [TimingConstraintSet] {
        _ = reference
        throw DFTConstraintError.loaderUnavailable
    }
}
