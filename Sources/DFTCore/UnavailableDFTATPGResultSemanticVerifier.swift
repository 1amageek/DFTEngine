import LogicIR

public struct UnavailableDFTATPGResultSemanticVerifier: DFTATPGResultSemanticVerifying {
    public init() {}

    public func validate(
        _ result: DFTResult,
        for request: DFTRequest,
        design: LogicDesignSnapshot
    ) async throws {
        throw DFTResultSemanticValidationError.semanticMismatch(
            "ATPG evidence requires an independently injected semantic replay verifier"
        )
    }
}
