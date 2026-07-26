import Foundation

public struct DFTPatternExchangeProgram: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var name: String
    public var signals: [DFTPatternSignal]
    public var signalGroups: [DFTPatternSignalGroup]
    public var timingSets: [DFTPatternTimingSet]
    public var procedures: [DFTPatternProcedure]
    public var patterns: [DFTPatternCase]

    public init(
        schemaVersion: Int = 1,
        name: String,
        signals: [DFTPatternSignal],
        signalGroups: [DFTPatternSignalGroup],
        timingSets: [DFTPatternTimingSet],
        procedures: [DFTPatternProcedure],
        patterns: [DFTPatternCase]
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.signals = signals
        self.signalGroups = signalGroups
        self.timingSets = timingSets
        self.procedures = procedures
        self.patterns = patterns
    }
}
