import Foundation

public struct DFTATPGConfiguration: Sendable, Hashable, Codable {
    public var maximumPatternCount: Int
    public var patternLength: Int
    public var abortLimit: Int
    public var randomSeed: UInt64?
    public var supportedProcessFamilies: [String]
    public var patternFormat: DFTTestPatternFormat
    public var faultSource: DFTATPGFaultSource?
    public var maximumExhaustiveInputCount: Int?
    public var maximumSequentialCycleCount: Int?
    public var sequentialCellContracts: [DFTSequentialCellContract]

    public init(
        maximumPatternCount: Int = 10_000,
        patternLength: Int = 32,
        abortLimit: Int = 0,
        randomSeed: UInt64? = nil,
        supportedProcessFamilies: [String] = [],
        patternFormat: DFTTestPatternFormat = .json,
        faultSource: DFTATPGFaultSource? = nil,
        maximumExhaustiveInputCount: Int? = 16,
        maximumSequentialCycleCount: Int? = nil,
        sequentialCellContracts: [DFTSequentialCellContract] = []
    ) {
        self.maximumPatternCount = maximumPatternCount
        self.patternLength = patternLength
        self.abortLimit = abortLimit
        self.randomSeed = randomSeed
        self.supportedProcessFamilies = supportedProcessFamilies
        self.patternFormat = patternFormat
        self.faultSource = faultSource
        self.maximumExhaustiveInputCount = maximumExhaustiveInputCount
        self.maximumSequentialCycleCount = maximumSequentialCycleCount
        self.sequentialCellContracts = sequentialCellContracts.sorted {
            $0.cellTypes.joined(separator: ",") < $1.cellTypes.joined(separator: ",")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case maximumPatternCount
        case patternLength
        case abortLimit
        case randomSeed
        case supportedProcessFamilies
        case patternFormat
        case faultSource
        case maximumExhaustiveInputCount
        case maximumSequentialCycleCount
        case sequentialCellContracts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maximumPatternCount: try container.decode(Int.self, forKey: .maximumPatternCount),
            patternLength: try container.decode(Int.self, forKey: .patternLength),
            abortLimit: try container.decode(Int.self, forKey: .abortLimit),
            randomSeed: try container.decodeIfPresent(UInt64.self, forKey: .randomSeed),
            supportedProcessFamilies: try container.decode(
                [String].self,
                forKey: .supportedProcessFamilies
            ),
            patternFormat: try container.decode(DFTTestPatternFormat.self, forKey: .patternFormat),
            faultSource: try container.decodeIfPresent(DFTATPGFaultSource.self, forKey: .faultSource),
            maximumExhaustiveInputCount: try container.decodeIfPresent(
                Int.self,
                forKey: .maximumExhaustiveInputCount
            ),
            maximumSequentialCycleCount: try container.decodeIfPresent(
                Int.self,
                forKey: .maximumSequentialCycleCount
            ),
            sequentialCellContracts: try container.decode(
                [DFTSequentialCellContract].self,
                forKey: .sequentialCellContracts
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(maximumPatternCount, forKey: .maximumPatternCount)
        try container.encode(patternLength, forKey: .patternLength)
        try container.encode(abortLimit, forKey: .abortLimit)
        try container.encodeIfPresent(randomSeed, forKey: .randomSeed)
        try container.encode(supportedProcessFamilies, forKey: .supportedProcessFamilies)
        try container.encode(patternFormat, forKey: .patternFormat)
        try container.encodeIfPresent(faultSource, forKey: .faultSource)
        try container.encodeIfPresent(
            maximumExhaustiveInputCount,
            forKey: .maximumExhaustiveInputCount
        )
        try container.encodeIfPresent(
            maximumSequentialCycleCount,
            forKey: .maximumSequentialCycleCount
        )
        try container.encode(sequentialCellContracts, forKey: .sequentialCellContracts)
    }

    public func replacingSequentialCellContracts(
        _ sequentialCellContracts: [DFTSequentialCellContract]
    ) -> DFTATPGConfiguration {
        DFTATPGConfiguration(
            maximumPatternCount: maximumPatternCount,
            patternLength: patternLength,
            abortLimit: abortLimit,
            randomSeed: randomSeed,
            supportedProcessFamilies: supportedProcessFamilies,
            patternFormat: patternFormat,
            faultSource: faultSource,
            maximumExhaustiveInputCount: maximumExhaustiveInputCount,
            maximumSequentialCycleCount: maximumSequentialCycleCount,
            sequentialCellContracts: sequentialCellContracts
        )
    }
}
