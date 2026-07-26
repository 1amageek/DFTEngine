import Foundation

public struct DFTScanImplementation: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var architectureName: String
    public var sourceDesignDigest: String
    public var transformedDesignDigest: String
    public var scanEnableSignal: String
    public var scanEnableNetID: String
    public var testModeSignal: String
    public var testModeNetID: String
    public var chains: [DFTRealizedScanChain]

    public init(
        architectureName: String,
        sourceDesignDigest: String,
        transformedDesignDigest: String,
        scanEnableSignal: String,
        scanEnableNetID: String,
        testModeSignal: String,
        testModeNetID: String,
        chains: [DFTRealizedScanChain]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.architectureName = architectureName
        self.sourceDesignDigest = sourceDesignDigest
        self.transformedDesignDigest = transformedDesignDigest
        self.scanEnableSignal = scanEnableSignal
        self.scanEnableNetID = scanEnableNetID
        self.testModeSignal = testModeSignal
        self.testModeNetID = testModeNetID
        self.chains = chains
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case architectureName
        case sourceDesignDigest
        case transformedDesignDigest
        case scanEnableSignal
        case scanEnableNetID
        case testModeSignal
        case testModeNetID
        case chains
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported scan implementation schema version \(schemaVersion)."
            )
        }
        architectureName = try container.decode(String.self, forKey: .architectureName)
        sourceDesignDigest = try container.decode(String.self, forKey: .sourceDesignDigest)
        transformedDesignDigest = try container.decode(String.self, forKey: .transformedDesignDigest)
        scanEnableSignal = try container.decode(String.self, forKey: .scanEnableSignal)
        scanEnableNetID = try container.decode(String.self, forKey: .scanEnableNetID)
        testModeSignal = try container.decode(String.self, forKey: .testModeSignal)
        testModeNetID = try container.decode(String.self, forKey: .testModeNetID)
        chains = try container.decode([DFTRealizedScanChain].self, forKey: .chains)
    }
}
