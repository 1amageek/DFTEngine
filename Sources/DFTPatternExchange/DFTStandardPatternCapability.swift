public struct DFTStandardPatternCapability: Sendable, Hashable, Codable {
    public var profileID: String
    public var standardVersion: String
    public var textEncoding: String
    public var timeUnit: String
    public var supportedActions: [DFTWaveformAction]
    public var supportsSignalGroups: Bool
    public var supportsProcedures: Bool
    public var supportsPatternBursts: Bool
    public var supportsEscapedIdentifiers: Bool

    public init(
        profileID: String,
        standardVersion: String,
        textEncoding: String,
        timeUnit: String,
        supportedActions: [DFTWaveformAction],
        supportsSignalGroups: Bool,
        supportsProcedures: Bool,
        supportsPatternBursts: Bool,
        supportsEscapedIdentifiers: Bool
    ) {
        self.profileID = profileID
        self.standardVersion = standardVersion
        self.textEncoding = textEncoding
        self.timeUnit = timeUnit
        self.supportedActions = supportedActions
        self.supportsSignalGroups = supportsSignalGroups
        self.supportsProcedures = supportsProcedures
        self.supportsPatternBursts = supportsPatternBursts
        self.supportsEscapedIdentifiers = supportsEscapedIdentifiers
    }
}
