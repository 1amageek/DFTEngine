import DFTCore
import Foundation
import PDKCore

public struct DFTRealizedScanATPGRequestConfiguration:
    Sendable, Hashable, Codable
{
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var constraints: DFTConstraintReference
    public var pdk: PDKReference
    public var clocks: [DFTScanClock]
    public var domainClockIDs: [String: String]
    public var atpg: DFTATPGConfiguration

    public init(
        runID: String,
        constraints: DFTConstraintReference,
        pdk: PDKReference,
        clocks: [DFTScanClock],
        domainClockIDs: [String: String],
        atpg: DFTATPGConfiguration
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.constraints = constraints
        self.pdk = pdk
        self.clocks = clocks
        self.domainClockIDs = domainClockIDs
        self.atpg = atpg
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case constraints
        case pdk
        case clocks
        case domainClockIDs
        case atpg
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription:
                    "Unsupported realized-scan ATPG configuration schema version \(schemaVersion)."
            )
        }
        runID = try container.decode(String.self, forKey: .runID)
        constraints = try container.decode(
            DFTConstraintReference.self,
            forKey: .constraints
        )
        pdk = try container.decode(PDKReference.self, forKey: .pdk)
        clocks = try container.decode([DFTScanClock].self, forKey: .clocks)
        domainClockIDs = try container.decode(
            [String: String].self,
            forKey: .domainClockIDs
        )
        atpg = try container.decode(
            DFTATPGConfiguration.self,
            forKey: .atpg
        )
    }
}
