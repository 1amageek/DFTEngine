public enum DFTPatternExchangeError: Error, Sendable, Hashable, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidIdentifier(context: String, value: String)
    case emptyCollection(String)
    case duplicateIdentifier(context: String, value: String)
    case unknownReference(context: String, value: String)
    case invalidPeriod(timingSet: String)
    case invalidWaveformSymbol(signal: String, symbol: String)
    case invalidWaveformEvent(signal: String, symbol: String, reason: String)
    case invalidAssignment(procedure: String, target: String, reason: String)
    case incompleteCycle(procedure: String, missingSignals: [String])
    case invalidTextEncoding
    case malformedSTIL(offset: Int, reason: String)
    case unsupportedSTILConstruct(keyword: String, offset: Int)
}
