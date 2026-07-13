import Foundation

public struct DFTTestPatternSet: Sendable, Hashable, Codable {
    public var format: String
    public var seed: UInt64
    public var faultUniverseDigest: String
    public var patterns: [DFTTestPattern]

    public init(
        format: String,
        seed: UInt64,
        faultUniverseDigest: String,
        patterns: [DFTTestPattern]
    ) {
        self.format = format
        self.seed = seed
        self.faultUniverseDigest = faultUniverseDigest
        self.patterns = patterns
    }
}
