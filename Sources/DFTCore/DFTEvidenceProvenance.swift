import Foundation

public struct DFTEvidenceProvenance: Sendable, Hashable, Codable {
    public var status: DFTEvidenceMaturity
    public var corpusRevision: String?
    public var oracleEvidence: String?
    public var processID: String?
    public var pdkDigest: String?
    public var requestDigests: [String]
    public var notes: [String]

    public init(
        status: DFTEvidenceMaturity,
        corpusRevision: String? = nil,
        oracleEvidence: String? = nil,
        processID: String? = nil,
        pdkDigest: String? = nil,
        requestDigests: [String] = [],
        notes: [String] = []
    ) {
        self.status = status
        self.corpusRevision = corpusRevision
        self.oracleEvidence = oracleEvidence
        self.processID = processID
        self.pdkDigest = pdkDigest
        self.requestDigests = requestDigests.sorted()
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case corpusRevision
        case oracleEvidence
        case processID
        case pdkDigest
        case requestDigests
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(DFTEvidenceMaturity.self, forKey: .status)
        corpusRevision = try container.decodeIfPresent(String.self, forKey: .corpusRevision)
        oracleEvidence = try container.decodeIfPresent(String.self, forKey: .oracleEvidence)
        processID = try container.decodeIfPresent(String.self, forKey: .processID)
        pdkDigest = try container.decodeIfPresent(String.self, forKey: .pdkDigest)
        requestDigests = (try container.decodeIfPresent([String].self, forKey: .requestDigests) ?? []).sorted()
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(corpusRevision, forKey: .corpusRevision)
        try container.encodeIfPresent(oracleEvidence, forKey: .oracleEvidence)
        try container.encodeIfPresent(processID, forKey: .processID)
        try container.encodeIfPresent(pdkDigest, forKey: .pdkDigest)
        try container.encode(requestDigests.sorted(), forKey: .requestDigests)
        try container.encode(notes, forKey: .notes)
    }
}
