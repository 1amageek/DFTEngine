import DFTCore
import Foundation

public struct ExternalATPGAdapter: ATPGExecuting {
    public let executor: DFTExternalToolExecutor

    public init(
        runner: any DFTExternalToolRunning,
        artifactStore: (any DFTArtifactStoring)? = nil
    ) {
        self.executor = DFTExternalToolExecutor(runner: runner, artifactStore: artifactStore)
    }

    public func execute(
        _ request: DFTRequest
    ) async throws -> DFTResult {
        try await executor.execute(request)
    }
}
