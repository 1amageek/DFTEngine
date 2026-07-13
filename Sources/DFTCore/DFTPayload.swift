import Foundation
import XcircuitePackage
import LogicIR

public struct DFTPayload: Sendable, Hashable, Codable {
    public var transformedDesign: LogicDesignReference?
    public var faultCoverage: Double?
    public var scanPlan: DFTScanPlan?
    public var designDiff: XcircuiteDesignDiff?
    public var patterns: DFTTestPatternSet?
    public var coverageEvidence: DFTCoverageEvidence?
    public var bistStructure: DFTBISTStructure?
    public var qualification: DFTQualificationProvenance
    public var assumptions: [String]

    public init(
        transformedDesign: LogicDesignReference?,
        faultCoverage: Double?,
        scanPlan: DFTScanPlan? = nil,
        designDiff: XcircuiteDesignDiff? = nil,
        patterns: DFTTestPatternSet? = nil,
        coverageEvidence: DFTCoverageEvidence? = nil,
        bistStructure: DFTBISTStructure? = nil,
        qualification: DFTQualificationProvenance = DFTQualificationProvenance(status: .unqualified),
        assumptions: [String] = []
    ) {
        self.transformedDesign = transformedDesign
        self.faultCoverage = faultCoverage
        self.scanPlan = scanPlan
        self.designDiff = designDiff
        self.patterns = patterns
        self.coverageEvidence = coverageEvidence
        self.bistStructure = bistStructure
        self.qualification = qualification
        self.assumptions = assumptions
    }

    private enum CodingKeys: String, CodingKey {
        case transformedDesign
        case faultCoverage
        case scanPlan
        case designDiff
        case patterns
        case coverageEvidence
        case bistStructure
        case qualification
        case assumptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transformedDesign = try container.decodeIfPresent(LogicDesignReference.self, forKey: .transformedDesign)
        faultCoverage = try container.decodeIfPresent(Double.self, forKey: .faultCoverage)
        scanPlan = try container.decodeIfPresent(DFTScanPlan.self, forKey: .scanPlan)
        designDiff = try container.decodeIfPresent(XcircuiteDesignDiff.self, forKey: .designDiff)
        patterns = try container.decodeIfPresent(DFTTestPatternSet.self, forKey: .patterns)
        coverageEvidence = try container.decodeIfPresent(DFTCoverageEvidence.self, forKey: .coverageEvidence)
        bistStructure = try container.decodeIfPresent(DFTBISTStructure.self, forKey: .bistStructure)
        qualification = try container.decodeIfPresent(
            DFTQualificationProvenance.self,
            forKey: .qualification
        ) ?? DFTQualificationProvenance(status: .unqualified)
        assumptions = try container.decodeIfPresent([String].self, forKey: .assumptions) ?? []
    }
}
