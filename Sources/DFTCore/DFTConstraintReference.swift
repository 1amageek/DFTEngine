import CircuiteFoundation
import Foundation

public struct DFTConstraintReference: Sendable, Hashable, Codable {
    public var modes: [DFTConstraintModeReference]

    public init(artifact: ArtifactReference, modeIDs: [String]) {
        self.modes = modeIDs.map {
            DFTConstraintModeReference(modeID: $0, artifact: artifact)
        }
    }

    public init(modes: [DFTConstraintModeReference]) {
        self.modes = modes
    }

    public var modeIDs: [String] {
        modes.map(\.modeID)
    }

    public var artifacts: [ArtifactReference] {
        var identities = Set<ArtifactReference>()
        return modes.map(\.artifact).filter { identities.insert($0).inserted }
    }

    private enum CodingKeys: String, CodingKey {
        case modes
        case artifact
        case modeIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let modes = try container.decodeIfPresent(
            [DFTConstraintModeReference].self,
            forKey: .modes
        ) {
            self.init(modes: modes)
        } else {
            let artifact = try container.decode(ArtifactReference.self, forKey: .artifact)
            let modeIDs = try container.decode([String].self, forKey: .modeIDs)
            self.init(artifact: artifact, modeIDs: modeIDs)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modes, forKey: .modes)
    }
}
