import DFTCore

public protocol DFTScanPatternExchangeConverting: Sendable {
    func program(
        from plan: DFTScanPatternExecutionPlan,
        name: String
    ) throws -> DFTPatternExchangeProgram
}
