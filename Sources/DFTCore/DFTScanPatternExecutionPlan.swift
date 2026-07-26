import Foundation

public struct DFTScanPatternExecutionPlan: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var scanImplementationDigest: String
    public var transformedDesignDigest: String
    public var clockSignal: String
    public var clockPeriodPicoseconds: UInt64
    public var scanEnableSignal: String
    public var testModeSignal: String
    public var patterns: [DFTScanPatternExecution]

    public init(
        scanImplementationDigest: String,
        transformedDesignDigest: String,
        clockSignal: String,
        clockPeriodPicoseconds: UInt64,
        scanEnableSignal: String,
        testModeSignal: String,
        patterns: [DFTScanPatternExecution]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.scanImplementationDigest = scanImplementationDigest
        self.transformedDesignDigest = transformedDesignDigest
        self.clockSignal = clockSignal
        self.clockPeriodPicoseconds = clockPeriodPicoseconds
        self.scanEnableSignal = scanEnableSignal
        self.testModeSignal = testModeSignal
        self.patterns = patterns
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case scanImplementationDigest
        case transformedDesignDigest
        case clockSignal
        case clockPeriodPicoseconds
        case scanEnableSignal
        case testModeSignal
        case patterns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported scan execution-plan schema version \(schemaVersion)."
            )
        }
        scanImplementationDigest = try container.decode(
            String.self,
            forKey: .scanImplementationDigest
        )
        transformedDesignDigest = try container.decode(
            String.self,
            forKey: .transformedDesignDigest
        )
        clockSignal = try container.decode(String.self, forKey: .clockSignal)
        clockPeriodPicoseconds = try container.decode(
            UInt64.self,
            forKey: .clockPeriodPicoseconds
        )
        scanEnableSignal = try container.decode(
            String.self,
            forKey: .scanEnableSignal
        )
        testModeSignal = try container.decode(String.self, forKey: .testModeSignal)
        patterns = try container.decode(
            [DFTScanPatternExecution].self,
            forKey: .patterns
        )
    }
}
