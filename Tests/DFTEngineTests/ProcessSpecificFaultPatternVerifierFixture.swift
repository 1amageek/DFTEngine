import DFTCore

struct ProcessSpecificFaultPatternVerifierFixture: DFTProcessFaultPatternVerifying {
    let verifierID = "fixture-independent-process-pattern-verifier"
    var acceptedPattern = "11111111"

    func validate(
        result: DFTProcessFaultModelResult,
        fault: DFTFault,
        request: DFTRequest,
        configuration: DFTATPGConfiguration
    ) async throws -> Bool {
        result.patternBits == acceptedPattern
            && result.modelID == "fixture-process-fault-model"
            && fault.processFamily == "leakage"
            && request.pdk.processID == "test-process"
            && configuration.patternLength == acceptedPattern.count
    }
}
