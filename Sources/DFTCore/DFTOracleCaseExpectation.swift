import Foundation
import XcircuitePackage

public struct DFTOracleCaseExpectation: Sendable, Hashable, Codable {
    public var expectedStatus: XcircuiteEngineExecutionStatus
    public var expectedTransformedDesignDigest: String?
    public var expectedFaultUniverseDigest: String?
    public var expectedDetectedFaultIDs: [String]
    public var expectedUntestableFaultIDs: [String]
    public var expectedAbortedFaultIDs: [String]
    public var expectedCoverage: Double?
    public var expectedPatternDigest: String?
    public var expectedBISTStructureDigest: String?

    public init(
        expectedStatus: XcircuiteEngineExecutionStatus,
        expectedTransformedDesignDigest: String? = nil,
        expectedFaultUniverseDigest: String? = nil,
        expectedDetectedFaultIDs: [String] = [],
        expectedUntestableFaultIDs: [String] = [],
        expectedAbortedFaultIDs: [String] = [],
        expectedCoverage: Double? = nil,
        expectedPatternDigest: String? = nil,
        expectedBISTStructureDigest: String? = nil
    ) {
        self.expectedStatus = expectedStatus
        self.expectedTransformedDesignDigest = expectedTransformedDesignDigest
        self.expectedFaultUniverseDigest = expectedFaultUniverseDigest
        self.expectedDetectedFaultIDs = expectedDetectedFaultIDs.sorted()
        self.expectedUntestableFaultIDs = expectedUntestableFaultIDs.sorted()
        self.expectedAbortedFaultIDs = expectedAbortedFaultIDs.sorted()
        self.expectedCoverage = expectedCoverage
        self.expectedPatternDigest = expectedPatternDigest
        self.expectedBISTStructureDigest = expectedBISTStructureDigest
    }
}
