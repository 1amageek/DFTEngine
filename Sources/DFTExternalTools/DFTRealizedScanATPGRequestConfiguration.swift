import DFTCore
import Foundation
import PDKCore

public struct DFTRealizedScanATPGRequestConfiguration:
    Sendable, Hashable, Codable
{
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var runID: String
    public var constraints: DFTConstraintReference
    public var pdk: PDKReference
    public var cellLibrary: DFTCellLibraryReference
    public var clocks: [DFTScanClock]
    public var domainClockIDs: [String: String]
    public var atpg: DFTATPGConfiguration
    public var inputBindings: [DFTArtifactBinding]

    public init(
        runID: String,
        constraints: DFTConstraintReference,
        pdk: PDKReference,
        cellLibrary: DFTCellLibraryReference,
        clocks: [DFTScanClock],
        domainClockIDs: [String: String],
        atpg: DFTATPGConfiguration,
        inputBindings: [DFTArtifactBinding]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.constraints = constraints
        self.pdk = pdk
        self.cellLibrary = cellLibrary
        self.clocks = clocks
        self.domainClockIDs = domainClockIDs
        self.atpg = atpg
        self.inputBindings = inputBindings
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case constraints
        case pdk
        case cellLibrary
        case clocks
        case domainClockIDs
        case atpg
        case inputBindings
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
        cellLibrary = try container.decode(
            DFTCellLibraryReference.self,
            forKey: .cellLibrary
        )
        clocks = try container.decode([DFTScanClock].self, forKey: .clocks)
        domainClockIDs = try container.decode(
            [String: String].self,
            forKey: .domainClockIDs
        )
        atpg = try container.decode(
            DFTATPGConfiguration.self,
            forKey: .atpg
        )
        inputBindings = try container.decode(
            [DFTArtifactBinding].self,
            forKey: .inputBindings
        )
    }
}
