import DFTCore
import Foundation

public struct ExternalATPGEngine: ATPGExecuting {
    public let executor: DFTExternalToolExecutor

    public init(
        runner: any DFTExternalToolOutputProviding,
        artifactStore: (any DFTArtifactStoring)? = nil
    ) {
        self.executor = DFTExternalToolExecutor(runner: runner, artifactStore: artifactStore)
    }

    public func execute(
        _ request: DFTRequest
    ) async throws -> DFTResult {
        guard request.operation == .atpg else {
            throw DFTExternalToolError.operationMismatch(
                expected: DFTOperation.atpg.rawValue,
                actual: request.operation.rawValue
            )
        }
        return try await executor.execute(request)
    }
}
