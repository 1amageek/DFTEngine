import Foundation

public protocol DFTExternalToolRunning: Sendable {
    var descriptor: DFTExternalToolDescriptor { get }

    func run(requestData: Data) async throws -> Data
}
