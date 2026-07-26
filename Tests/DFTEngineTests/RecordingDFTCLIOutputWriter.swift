@testable import DFTCLIKit
import Synchronization

final class RecordingDFTCLIOutputWriter: DFTCLIOutputWriting, Sendable {
    private struct State: Sendable {
        var output: [String] = []
        var errors: [String] = []
    }

    private let state = Mutex(State())

    func writeOutput(_ value: String) {
        state.withLock { $0.output.append(value) }
    }

    func writeError(_ value: String) {
        state.withLock { $0.errors.append(value) }
    }

    var output: [String] {
        state.withLock { $0.output }
    }

    var errors: [String] {
        state.withLock { $0.errors }
    }
}
