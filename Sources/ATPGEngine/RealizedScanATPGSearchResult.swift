import DFTCore

public struct RealizedScanATPGSearchResult: Sendable, Hashable {
    public var outcomes: [DFTFaultOutcome]
    public var patterns: [DFTTestPattern]
    public var diagnostics: [DFTDiagnostic]
    public var abortedCount: Int
    public var untestableCount: Int
    public var executionPlan: DFTScanPatternExecutionPlan

    public init(
        outcomes: [DFTFaultOutcome],
        patterns: [DFTTestPattern],
        diagnostics: [DFTDiagnostic],
        abortedCount: Int,
        untestableCount: Int,
        executionPlan: DFTScanPatternExecutionPlan
    ) {
        self.outcomes = outcomes
        self.patterns = patterns
        self.diagnostics = diagnostics
        self.abortedCount = abortedCount
        self.untestableCount = untestableCount
        self.executionPlan = executionPlan
    }
}
