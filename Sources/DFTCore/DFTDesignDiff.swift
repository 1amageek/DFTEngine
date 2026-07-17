import CircuiteFoundation
import Foundation

public struct DFTDesignDiff: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var runID: String
    public var title: String
    public var actor: String
    public var baseSnapshot: ArtifactReference?
    public var proposedSnapshot: ArtifactReference?
    public var changes: [DFTDesignDiffChange]
    public var createdAt: Date

    public init(
        runID: String,
        title: String,
        actor: String,
        baseSnapshot: ArtifactReference? = nil,
        proposedSnapshot: ArtifactReference? = nil,
        changes: [DFTDesignDiffChange],
        createdAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.title = title
        self.actor = actor
        self.baseSnapshot = baseSnapshot
        self.proposedSnapshot = proposedSnapshot
        self.changes = changes
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case title
        case actor
        case baseSnapshot
        case proposedSnapshot
        case changes
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported DFT design diff schema version \(schemaVersion)."
            )
        }
        runID = try container.decode(String.self, forKey: .runID)
        title = try container.decode(String.self, forKey: .title)
        actor = try container.decode(String.self, forKey: .actor)
        baseSnapshot = try container.decodeIfPresent(ArtifactReference.self, forKey: .baseSnapshot)
        proposedSnapshot = try container.decodeIfPresent(ArtifactReference.self, forKey: .proposedSnapshot)
        changes = try container.decode([DFTDesignDiffChange].self, forKey: .changes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}
