import Foundation
import LogicIR

public struct DFTPayload: Sendable, Hashable, Codable {
    public var transformedDesign: LogicDesignReference?
    public var faultCoverage: Double?
    public var scanPlan: DFTScanPlan?
    public var scanImplementation: DFTScanImplementation?
    public var designDiff: DFTDesignDiff?
    public var patterns: DFTTestPatternSet?
    public var scanPatternExecutionPlan: DFTScanPatternExecutionPlan?
    public var coverageEvidence: DFTCoverageEvidence?
    public var bistStructure: DFTBISTStructure?
    public var evidenceProvenance: DFTEvidenceProvenance
    public var assumptions: [String]

    public init(
        transformedDesign: LogicDesignReference?,
        faultCoverage: Double?,
        scanPlan: DFTScanPlan? = nil,
        scanImplementation: DFTScanImplementation? = nil,
        designDiff: DFTDesignDiff? = nil,
        patterns: DFTTestPatternSet? = nil,
        scanPatternExecutionPlan: DFTScanPatternExecutionPlan? = nil,
        coverageEvidence: DFTCoverageEvidence? = nil,
        bistStructure: DFTBISTStructure? = nil,
        evidenceProvenance: DFTEvidenceProvenance = DFTEvidenceProvenance(status: .unassessed),
        assumptions: [String] = []
    ) {
        self.transformedDesign = transformedDesign
        self.faultCoverage = faultCoverage
        self.scanPlan = scanPlan
        self.scanImplementation = scanImplementation
        self.designDiff = designDiff
        self.patterns = patterns
        self.scanPatternExecutionPlan = scanPatternExecutionPlan
        self.coverageEvidence = coverageEvidence
        self.bistStructure = bistStructure
        self.evidenceProvenance = evidenceProvenance
        self.assumptions = assumptions
    }

    private enum CodingKeys: String, CodingKey {
        case transformedDesign
        case faultCoverage
        case scanPlan
        case scanImplementation
        case designDiff
        case patterns
        case scanPatternExecutionPlan
        case coverageEvidence
        case bistStructure
        case evidenceProvenance
        case assumptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transformedDesign = try container.decodeIfPresent(LogicDesignReference.self, forKey: .transformedDesign)
        faultCoverage = try container.decodeIfPresent(Double.self, forKey: .faultCoverage)
        scanPlan = try container.decodeIfPresent(DFTScanPlan.self, forKey: .scanPlan)
        scanImplementation = try container.decodeIfPresent(
            DFTScanImplementation.self,
            forKey: .scanImplementation
        )
        designDiff = try container.decodeIfPresent(DFTDesignDiff.self, forKey: .designDiff)
        patterns = try container.decodeIfPresent(DFTTestPatternSet.self, forKey: .patterns)
        scanPatternExecutionPlan = try container.decodeIfPresent(
            DFTScanPatternExecutionPlan.self,
            forKey: .scanPatternExecutionPlan
        )
        coverageEvidence = try container.decodeIfPresent(DFTCoverageEvidence.self, forKey: .coverageEvidence)
        bistStructure = try container.decodeIfPresent(DFTBISTStructure.self, forKey: .bistStructure)
        evidenceProvenance = try container.decode(
            DFTEvidenceProvenance.self,
            forKey: .evidenceProvenance
        )
        assumptions = try container.decode([String].self, forKey: .assumptions)
    }
}
