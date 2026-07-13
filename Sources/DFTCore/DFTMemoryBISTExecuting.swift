import Foundation

public protocol DFTMemoryBISTExecuting: Sendable {
    func execute(
        _ request: DFTRequest
    ) async throws -> DFTResult
}
