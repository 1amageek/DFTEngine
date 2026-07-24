import TimingCore

public protocol DFTConstraintLoading: Sendable {
    func load(_ reference: DFTConstraintReference) throws -> [TimingConstraintSet]
}
