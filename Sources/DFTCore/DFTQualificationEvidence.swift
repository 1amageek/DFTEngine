import Foundation
import XcircuitePackage

public struct DFTQualificationEvidence: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var evidenceID: String
    public var engineID: String
    public var implementationID: String
    public var processID: String
    public var pdkDigest: String
    public var corpusRevision: String
    public var totalCaseCount: Int
    public var passedCaseCount: Int
    public var oracleEvidenceDigest: String
    public var approvedBy: String?
    public var artifacts: [XcircuiteFileReference]

    public init(
        evidenceID: String,
        engineID: String,
        implementationID: String,
        processID: String,
        pdkDigest: String,
        corpusRevision: String,
        totalCaseCount: Int,
        passedCaseCount: Int,
        oracleEvidenceDigest: String,
        approvedBy: String? = nil,
        artifacts: [XcircuiteFileReference] = [],
        schemaVersion: Int = DFTQualificationEvidence.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.evidenceID = evidenceID
        self.engineID = engineID
        self.implementationID = implementationID
        self.processID = processID
        self.pdkDigest = pdkDigest
        self.corpusRevision = corpusRevision
        self.totalCaseCount = totalCaseCount
        self.passedCaseCount = passedCaseCount
        self.oracleEvidenceDigest = oracleEvidenceDigest
        self.approvedBy = approvedBy
        self.artifacts = artifacts
    }
}
