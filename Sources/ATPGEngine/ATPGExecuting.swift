import Foundation
import DFTCore

public protocol ATPGExecuting: Sendable {
    func execute(
        _ request: DFTRequest
    ) async throws -> DFTResult
}

