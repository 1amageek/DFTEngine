import Foundation

public protocol DFTProcessFaultPatternVerifying: Sendable {
    var verifierID: String { get }

    func validate(
        result: DFTProcessFaultModelResult,
        fault: DFTFault,
        request: DFTRequest,
        configuration: DFTATPGConfiguration
    ) async throws -> Bool
}
