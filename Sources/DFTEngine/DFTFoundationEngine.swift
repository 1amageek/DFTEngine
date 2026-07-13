import CircuiteFoundation
import DFTCore
import Foundation

/// Foundation-native execution seam for the DFT domain.
public protocol DFTFoundationExecuting: Engine
where Request == DFTRequest, Output == DFTResult {}

/// Foundation-native DFT execution implementation.
public struct DFTFoundationEngine: DFTFoundationExecuting {
    private let engine: any DFTEngineExecuting

    public init(engine: any DFTEngineExecuting) {
        self.engine = engine
    }

    public func execute(_ request: DFTRequest) async throws -> DFTResult {
        try await engine.execute(request)
    }
}
