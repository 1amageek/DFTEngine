import DFTCore

struct ProcessSpecificFaultModelFixture: DFTProcessFaultModeling {
    let modelID = "fixture-process-fault-model"
    var captureTiming = DFTProcessCaptureTiming(
        clockSignal: "scan_clk",
        launchEdge: .rising,
        captureEdge: .rising,
        launchToCaptureNanoseconds: 10,
        sampleOffsetNanoseconds: 9,
        assumptions: ["fixture timing is bound to the declared scan clock"]
    )

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
            captureTiming: captureTiming,
            reason: "fixture model evaluated \(fault.id) for \(request.pdk.processID)"
        )
    }
}
