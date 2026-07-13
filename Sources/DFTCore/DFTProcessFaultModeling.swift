import Foundation

public protocol DFTProcessFaultModeling: Sendable {
    var modelID: String { get }

    func supports(processFamily: String) -> Bool

    func evaluate(
        fault: DFTFault,
        request: DFTRequest,
        configuration: DFTATPGConfiguration
    ) async throws -> DFTProcessFaultModelResult
}
