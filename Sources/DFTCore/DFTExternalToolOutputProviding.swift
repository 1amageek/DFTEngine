import Foundation

public protocol DFTExternalToolOutputProviding: DFTExternalToolRunning {
    func runWithOutput(requestData: Data) async throws -> DFTExternalToolOutput
}
