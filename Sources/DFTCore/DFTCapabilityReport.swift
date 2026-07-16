import Foundation

public struct DFTCapabilityReport: Sendable, Hashable, Codable {
    public var engineID: String
    public var implementationID: String
    public var implementationVersion: String
    public var capabilities: [String: DFTCapabilityStatus]
    public var limitations: [String]
    public var evidenceProvenance: DFTEvidenceProvenance

    public init(
        engineID: String,
        implementationID: String,
        implementationVersion: String,
        capabilities: [String: DFTCapabilityStatus],
        limitations: [String],
        evidenceProvenance: DFTEvidenceProvenance
    ) {
        self.engineID = engineID
        self.implementationID = implementationID
        self.implementationVersion = implementationVersion
        self.capabilities = capabilities
        self.limitations = limitations
        self.evidenceProvenance = evidenceProvenance
    }
}
