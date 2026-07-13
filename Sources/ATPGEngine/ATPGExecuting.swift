import Foundation
import XcircuitePackage
import DFTCore

public protocol ATPGExecuting: Sendable {
    func execute(
        _ request: DFTRequest
    ) async throws -> XcircuiteEngineResultEnvelope<DFTPayload>
}

