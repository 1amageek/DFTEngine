public protocol DFTPatternExchangeValidating: Sendable {
    func validate(_ program: DFTPatternExchangeProgram) throws
}
