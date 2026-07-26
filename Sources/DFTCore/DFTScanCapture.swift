import Foundation

public struct DFTScanCapture: Sendable, Hashable, Codable {
    public var primaryInputs: [String: Bool]
    public var expectedPrimaryOutputs: [String: Bool]

    public init(
        primaryInputs: [String: Bool],
        expectedPrimaryOutputs: [String: Bool]
    ) {
        self.primaryInputs = primaryInputs
        self.expectedPrimaryOutputs = expectedPrimaryOutputs
    }
}
