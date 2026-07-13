import Foundation
import DFTCore

public protocol ScanInserting: Sendable {
    func execute(
        _ request: DFTRequest
    ) async throws -> DFTResult
}
