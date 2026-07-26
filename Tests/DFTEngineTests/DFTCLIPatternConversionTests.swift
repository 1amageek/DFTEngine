import DFTCore
@testable import DFTCLIKit
import DFTPatternExchange
import Foundation
import Testing

@Suite("DFT CLI pattern conversion")
struct DFTCLIPatternConversionTests {
    @Test("neutral scan execution plan converts to retained STIL")
    func convertsPlanToSTIL() async throws {
        let root = try temporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let planURL = root.appending(path: "execution-plan.json")
        let resultURL = root.appending(path: "patterns.stil")
        try DFTArtifactJSONEncoder().encode(executionPlan()).write(
            to: planURL,
            options: .atomic
        )

        let exitCode = try await DFTCLICommand().run(arguments: [
            "convert-scan-pattern",
            "--plan", planURL.path,
            "--name", "hosted_scan",
            "--format", "stil",
            "--result", resultURL.path,
        ])

        #expect(exitCode == 0)
        let retained = try Data(
            contentsOf: resultURL,
            options: .mappedIfSafe
        )
        let program = try STILPatternCodec().decode(retained)
        #expect(program.name == "hosted_scan")
        #expect(program.patterns.map(\.id) == ["pattern_0"])
        #expect(program.procedures.first?.cycles.count == 5)
    }

    @Test("unsupported output format fails explicitly")
    func rejectsUnsupportedFormat() async throws {
        let root = try temporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let planURL = root.appending(path: "execution-plan.json")
        try DFTArtifactJSONEncoder().encode(executionPlan()).write(
            to: planURL,
            options: .atomic
        )

        await #expect(throws: DFTCLIError.self) {
            _ = try await DFTCLICommand().run(arguments: [
                "convert-scan-pattern",
                "--plan", planURL.path,
                "--name", "hosted_scan",
                "--format", "wgl",
            ])
        }
    }

    private func executionPlan() -> DFTScanPatternExecutionPlan {
        DFTScanPatternExecutionPlan(
            scanImplementationDigest: String(repeating: "a", count: 64),
            transformedDesignDigest: String(repeating: "b", count: 64),
            clockSignal: "clk",
            clockPeriodPicoseconds: 10_000,
            scanEnableSignal: "scan_enable",
            testModeSignal: "test_mode",
            patterns: [
                DFTScanPatternExecution(
                    id: "pattern_0",
                    faultIDs: ["fault_0"],
                    chains: [
                        DFTScanChainStimulus(
                            chainID: "chain_0",
                            scanInSignal: "scan_in",
                            scanOutSignal: "q",
                            elementOutputNetIDs: ["q0", "q"],
                            loadBits: "10",
                            expectedUnloadBits: "01"
                        ),
                    ],
                    capture: DFTScanCapture(
                        primaryInputs: [
                            "clk": false,
                            "d": true,
                            "scan_enable": false,
                            "scan_in": false,
                            "test_mode": true,
                        ],
                        expectedPrimaryOutputs: ["q": true]
                    )
                ),
            ]
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "dft-cli-pattern-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false
        )
        return url
    }

    private func removeTemporaryDirectory(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Failed to remove DFT CLI pattern directory: \(error)")
        }
    }
}
