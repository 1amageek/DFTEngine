import Foundation

public struct DFTOracleCorpus: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var corpusID: String
    public var revision: String
    public var processID: String
    public var pdkDigest: String
    public var cases: [DFTOracleCorpusCase]

    public init(
        corpusID: String,
        revision: String,
        processID: String,
        pdkDigest: String,
        cases: [DFTOracleCorpusCase],
        schemaVersion: Int = DFTOracleCorpus.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.corpusID = corpusID
        self.revision = revision
        self.processID = processID
        self.pdkDigest = pdkDigest
        self.cases = cases.sorted { $0.caseID < $1.caseID }
    }
}
