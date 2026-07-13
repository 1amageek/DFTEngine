import Foundation

public struct DFTReleaseDownstreamEvidence: Sendable, Hashable, Codable {
    public enum Domain: String, Sendable, Hashable, Codable {
        case equivalence
        case drc
        case lvs
        case pex
        case timing
    }

    public var domain: Domain
    public var role: String
    public var artifact: DFTArtifactReference

    public init(
        domain: Domain,
        role: String,
        artifact: DFTArtifactReference
    ) {
        self.domain = domain
        self.role = role
        self.artifact = artifact
    }
}
