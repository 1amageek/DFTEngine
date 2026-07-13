import Foundation

public struct DFTCoverageEvidence: Sendable, Hashable, Codable {
    public var faultUniverseName: String
    public var faultUniverseRevision: String
    public var faultUniverseDigest: String
    public var declaredFaultCount: Int
    public var excludedFaultCount: Int
    public var detectedFaultCount: Int
    public var untestableFaultCount: Int
    public var abortedFaultCount: Int
    public var coverage: Double?
    public var assumptions: [String]
    public var qualification: DFTQualificationProvenance
    public var outcomes: [DFTFaultOutcome]

    public init(
        faultUniverseName: String,
        faultUniverseRevision: String,
        faultUniverseDigest: String,
        declaredFaultCount: Int,
        excludedFaultCount: Int,
        detectedFaultCount: Int,
        untestableFaultCount: Int,
        abortedFaultCount: Int,
        coverage: Double?,
        assumptions: [String],
        qualification: DFTQualificationProvenance,
        outcomes: [DFTFaultOutcome]
    ) {
        self.faultUniverseName = faultUniverseName
        self.faultUniverseRevision = faultUniverseRevision
        self.faultUniverseDigest = faultUniverseDigest
        self.declaredFaultCount = declaredFaultCount
        self.excludedFaultCount = excludedFaultCount
        self.detectedFaultCount = detectedFaultCount
        self.untestableFaultCount = untestableFaultCount
        self.abortedFaultCount = abortedFaultCount
        self.coverage = coverage
        self.assumptions = assumptions
        self.qualification = qualification
        self.outcomes = outcomes
    }
}
