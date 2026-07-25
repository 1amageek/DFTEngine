import Foundation

public struct DFTProcessCaptureTimingValidator: Sendable {
    public init() {}

    public func validate(
        _ timing: DFTProcessCaptureTiming,
        architecture: DFTScanArchitecture?
    ) throws {
        guard let clock = architecture?.clocks.first(where: {
            $0.signalName == timing.clockSignal
        }) else {
            throw DFTProcessCaptureTimingValidationError.clockNotDeclared(
                timing.clockSignal
            )
        }
        guard timing.launchToCaptureNanoseconds.isFinite,
              timing.launchToCaptureNanoseconds > 0,
              timing.launchToCaptureNanoseconds <= clock.periodNanoseconds else {
            throw DFTProcessCaptureTimingValidationError.launchToCaptureInvalid(
                timing.launchToCaptureNanoseconds
            )
        }
        guard timing.sampleOffsetNanoseconds.isFinite,
              timing.sampleOffsetNanoseconds >= 0,
              timing.sampleOffsetNanoseconds
                <= timing.launchToCaptureNanoseconds else {
            throw DFTProcessCaptureTimingValidationError.sampleOffsetInvalid(
                timing.sampleOffsetNanoseconds
            )
        }
        guard !timing.assumptions.isEmpty,
              timing.assumptions.allSatisfy({
                  !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            throw DFTProcessCaptureTimingValidationError.assumptionsMissing
        }
    }
}
