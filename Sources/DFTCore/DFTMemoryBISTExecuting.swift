import Foundation
import XcircuitePackage

public protocol DFTMemoryBISTExecuting: Sendable {
    func execute(
        _ request: DFTRequest
    ) async throws -> XcircuiteEngineResultEnvelope<DFTPayload>
}
