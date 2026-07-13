import DFTCore

struct ProcessSpecificFaultModelFixture: DFTProcessFaultModeling {
    let modelID = "fixture-process-fault-model"

    func supports(processFamily: String) -> Bool {
        processFamily == "leakage"
    }

    func evaluate(
        fault: DFTFault,
        request: DFTRequest,
        configuration: DFTATPGConfiguration
    ) async throws -> DFTProcessFaultModelResult {
        DFTProcessFaultModelResult(
            modelID: modelID,
            status: .detected,
            patternBits: String(repeating: "1", count: configuration.patternLength),
            reason: "fixture model evaluated \(fault.id) for \(request.pdk.processID)"
        )
    }
}
