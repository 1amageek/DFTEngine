import Foundation
import DFTCore

public protocol BISTExecuting: Sendable {
    func execute(
        _ request: DFTRequest
    ) async throws -> DFTResult
}

