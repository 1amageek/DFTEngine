import Foundation
import XcircuitePackage
import DFTCore

public protocol BISTExecuting: Sendable {
    func execute(
        _ request: DFTRequest
    ) async throws -> XcircuiteEngineResultEnvelope<DFTPayload>
}

