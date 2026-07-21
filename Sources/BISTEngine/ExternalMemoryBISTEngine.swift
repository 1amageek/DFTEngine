import DFTCore
import Foundation

public struct ExternalMemoryBISTEngine: BISTExecuting, DFTMemoryBISTExecuting {
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
        guard request.operation == .bist else {
            throw DFTMemoryBISTExecutionError.operationMismatch
        }
        guard let configuration = request.bistConfiguration,
              configuration.kind == .memory else {
            throw DFTMemoryBISTExecutionError.configurationMissing
        }
        guard configuration.memoryBindings?.isEmpty == false,
              configuration.memoryBindings?.allSatisfy(\.isStructurallyComplete) == true else {
            throw DFTMemoryBISTExecutionError.bindingsMissing
        }
        let result = try await executor.execute(request)
        guard result.status == .completed else {
            throw DFTMemoryBISTExecutionError.resultNotCompleted(result.status)
        }
        return result
    }
}
