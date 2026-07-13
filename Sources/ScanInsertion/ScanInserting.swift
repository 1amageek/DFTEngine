import Foundation
import XcircuitePackage
import DFTCore

public protocol ScanInserting: Sendable {
    func execute(
        _ request: DFTRequest
    ) async throws -> XcircuiteEngineResultEnvelope<DFTPayload>
}
