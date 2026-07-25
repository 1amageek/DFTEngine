import LogicIR

public protocol DFTATPGResultSemanticVerifying: Sendable {
    func validate(
        _ result: DFTResult,
        for request: DFTRequest,
        design: LogicDesignSnapshot
    ) async throws
}
