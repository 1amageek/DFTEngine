import CircuiteFoundation
import DFTCore
@testable import DFTExternalTools
import DFTPatternExchange
import Foundation
import Testing

@Suite("Icarus DFT scan-pattern replay provider")
struct IcarusDFTScanPatternReplayProviderTests {
    @Test("retained STIL becomes a cycle-accurate fault-aware harness")
    func buildsHarness() throws {
        let program = try STILPatternCodec().decode(patternFixture())
        let harness = try VerilogDFTReplayHarnessBuilder().build(
            program: program,
            topModule: "scan_dut",
            faults: [
                DFTScanPatternReplayFault(
                    faultID: "scan-out-sa1",
                    hierarchicalSignalPath: "scan_out",
                    stuckAtValue: true
                ),
            ]
        )
        let text = try #require(String(data: harness, encoding: .utf8))

        #expect(text.contains("force dut.scan_out = 1'b1;"))
        #expect(text.contains("#9000;"))
        #expect(text.contains("#1000;"))
        #expect(text.contains("DFT_REPLAY_GOLDEN_COMPLETE"))
        #expect(text.contains("DFT_REPLAY_RESULT index=%0d mismatches=%0d"))
        #expect(text.contains("!== 1'b0"))
    }

    @Test("provider retains compile, golden, and fault evidence")
    func replaysAndRetainsEvidence() async throws {
        let workspace = try temporaryDirectory()
        defer { removeTemporaryDirectory(workspace) }
        let compiler = try fakeCompiler(in: workspace)
        let simulator = try fakeSimulator(in: workspace)
        let store = InMemoryDFTArtifactStore()
        let request = try await replayRequest(store: store)
        let provider = try provider(
            compiler: compiler,
            simulator: simulator,
            store: store
        )

        let result = try await provider.replay(request)

        #expect(result.runID == request.runID)
        #expect(result.inputs == [
            request.patternArtifact,
            request.scanNetlistArtifact,
            request.scanImplementation.artifact,
            request.faultUniverseArtifact,
        ] + request.cellModelArtifacts)
        #expect(result.scanImplementationDigest.count == 64)
        #expect(result.faultUniverseDigest.count == 64)
        #expect(result.observations == [
            DFTScanPatternReplayObservation(
                faultID: "scan-out-sa1",
                detected: true,
                mismatchCount: 1
            ),
        ])
        #expect(result.artifacts.count == 3)
        for artifact in result.artifacts {
            let data = try await store.data(for: artifact)
            #expect(!data.isEmpty)
        }
    }

    @Test("tampered retained input fails before external execution")
    func rejectsTamperedInput() async throws {
        let workspace = try temporaryDirectory()
        defer { removeTemporaryDirectory(workspace) }
        let compiler = try fakeCompiler(in: workspace)
        let simulator = try fakeSimulator(in: workspace)
        let store = InMemoryDFTArtifactStore()
        var request = try await replayRequest(store: store)
        request.patternArtifact = ArtifactReference(
            id: request.patternArtifact.id,
            locator: request.patternArtifact.locator,
            digest: request.patternArtifact.digest,
            byteCount: request.patternArtifact.byteCount + 1,
            producer: request.patternArtifact.producer
        )
        let provider = try provider(
            compiler: compiler,
            simulator: simulator,
            store: store
        )

        await #expect(throws: DFTScanPatternReplayError.self) {
            _ = try await provider.replay(request)
        }
    }

    @Test("golden mismatch is not accepted as a fault observation")
    func rejectsGoldenMismatch() async throws {
        let workspace = try temporaryDirectory()
        defer { removeTemporaryDirectory(workspace) }
        let compiler = try fakeCompiler(in: workspace)
        let simulator = try executable(
            named: "failing-vvp",
            script: """
            #!/bin/sh
            printf '%s\n' 'DFT_REPLAY_GOLDEN_MISMATCH count=1'
            exit 1
            """,
            in: workspace
        )
        let store = InMemoryDFTArtifactStore()
        let request = try await replayRequest(store: store)
        let provider = try provider(
            compiler: compiler,
            simulator: simulator,
            store: store
        )

        do {
            _ = try await provider.replay(request)
            Issue.record("Expected golden replay mismatch")
        } catch let error as DFTScanPatternReplayError {
            guard case .goldenReplayMismatch = error else {
                Issue.record("Unexpected replay error: \(error)")
                return
            }
        }
    }

    @Test("fault replay without a structured result marker fails")
    func rejectsMissingFaultResult() async throws {
        let workspace = try temporaryDirectory()
        defer { removeTemporaryDirectory(workspace) }
        let compiler = try fakeCompiler(in: workspace)
        let simulator = try executable(
            named: "incomplete-vvp",
            script: """
            #!/bin/sh
            case "$*" in
              *+DFT_FAULT_INDEX=*)
                printf '%s\n' 'SIMULATION_COMPLETE_WITHOUT_RESULT'
                ;;
              *)
                printf '%s\n' 'DFT_REPLAY_GOLDEN_COMPLETE'
                ;;
            esac
            """,
            in: workspace
        )
        let store = InMemoryDFTArtifactStore()
        let request = try await replayRequest(store: store)
        let provider = try provider(
            compiler: compiler,
            simulator: simulator,
            store: store
        )

        do {
            _ = try await provider.replay(request)
            Issue.record("Expected missing fault result to fail")
        } catch let error as DFTScanPatternReplayError {
            guard case .replayOutputInvalid = error else {
                Issue.record("Unexpected replay error: \(error)")
                return
            }
        }
    }

    @Test("compiler identity mismatch fails before launch")
    func rejectsCompilerIdentityMismatch() async throws {
        let workspace = try temporaryDirectory()
        defer { removeTemporaryDirectory(workspace) }
        let compiler = try fakeCompiler(in: workspace)
        let simulator = try fakeSimulator(in: workspace)
        let store = InMemoryDFTArtifactStore()
        let request = try await replayRequest(store: store)
        let provider = try provider(
            compiler: compiler,
            simulator: simulator,
            store: store,
            compilerDigest: String(repeating: "0", count: 64)
        )

        do {
            _ = try await provider.replay(request)
            Issue.record("Expected executable identity mismatch")
        } catch let error as DFTScanPatternReplayError {
            guard case .executableIdentityMismatch = error else {
                Issue.record("Unexpected replay error: \(error)")
                return
            }
        }
    }

    @Test("compiler timeout is mapped to the replay error contract")
    func reportsCompilerTimeout() async throws {
        let workspace = try temporaryDirectory()
        defer { removeTemporaryDirectory(workspace) }
        let compiler = try executable(
            named: "slow-iverilog",
            script: """
            #!/bin/sh
            sleep 2
            """,
            in: workspace
        )
        let simulator = try fakeSimulator(in: workspace)
        let store = InMemoryDFTArtifactStore()
        let request = try await replayRequest(store: store)
        let provider = try provider(
            compiler: compiler,
            simulator: simulator,
            store: store,
            timeoutSeconds: 0.05
        )

        do {
            _ = try await provider.replay(request)
            Issue.record("Expected compiler timeout")
        } catch let error as DFTScanPatternReplayError {
            guard case .processTimedOut(
                implementationID: "iverilog-test",
                timeoutSeconds: 0.05
            ) = error else {
                Issue.record("Unexpected replay error: \(error)")
                return
            }
        }
    }

    @Test(
        "task cancellation terminates replay and uses the replay error contract",
        .timeLimit(.minutes(1))
    )
    func reportsCancellation() async throws {
        let workspace = try temporaryDirectory()
        defer { removeTemporaryDirectory(workspace) }
        let compiler = try executable(
            named: "cancellable-iverilog",
            script: """
            #!/bin/sh
            sleep 2
            """,
            in: workspace
        )
        let simulator = try fakeSimulator(in: workspace)
        let store = InMemoryDFTArtifactStore()
        let request = try await replayRequest(store: store)
        let provider = try provider(
            compiler: compiler,
            simulator: simulator,
            store: store
        )
        let task = Task {
            try await provider.replay(request)
        }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected replay cancellation")
        } catch let error as DFTScanPatternReplayError {
            guard case .processCancelled(
                implementationID: "iverilog-test"
            ) = error else {
                Issue.record("Unexpected replay error: \(error)")
                return
            }
        }
    }

    @Test("empty fault corpus is rejected before execution")
    func rejectsEmptyFaultCorpus() async throws {
        let workspace = try temporaryDirectory()
        defer { removeTemporaryDirectory(workspace) }
        let compiler = try fakeCompiler(in: workspace)
        let simulator = try fakeSimulator(in: workspace)
        let store = InMemoryDFTArtifactStore()
        var request = try await replayRequest(store: store)
        request.faultIDs = []
        let provider = try provider(
            compiler: compiler,
            simulator: simulator,
            store: store
        )

        await #expect(throws: DFTScanPatternReplayError.self) {
            _ = try await provider.replay(request)
        }
    }

    @Test("realized scan validator rejects disconnected element order")
    func rejectsInvalidRealizedScanStructure() {
        var implementation = scanImplementationFixture()
        implementation.chains[0].elements[0].position = 1

        let issues = DFTScanImplementationValidator()
            .validationIssues(in: implementation)

        #expect(issues.map(\.code).contains(
            "DFT_SCAN_IMPLEMENTATION_ELEMENT_INVALID"
        ))
    }

    private func replayRequest(
        store: InMemoryDFTArtifactStore
    ) async throws -> DFTScanPatternReplayRequest {
        let runID = "icarus-replay-test"
        let pattern = try await store.store(
            DFTArtifactContent(
                artifactID: "replay-pattern",
                fileName: "pattern.stil",
                kind: .testPattern,
                format: .stil,
                data: try providerPatternFixture()
            ),
            runID: runID
        )
        let netlist = try await store.store(
            DFTArtifactContent(
                artifactID: "replay-netlist",
                fileName: "scan-netlist.v",
                kind: .netlist,
                format: .verilog,
                data: Data(
                    """
                    module scan_dut(
                        input scan_clk,
                        input scan_in,
                        input scan_en,
                        input test_mode,
                        output scan_out
                    );
                        assign scan_out = scan_in;
                    endmodule
                    """.utf8
                )
            ),
            runID: runID
        )
        let model = try await store.store(
            DFTArtifactContent(
                artifactID: "replay-cell-model",
                fileName: "cell-model.v",
                kind: .model,
                format: .verilog,
                data: Data("module unused_cell_model; endmodule\n".utf8)
            ),
            runID: runID
        )
        let scanImplementation = scanImplementationFixture()
        let scanImplementationReference = try await store.store(
            DFTArtifactContent(
                artifactID: "replay-scan-implementation",
                fileName: "scan-implementation.json",
                kind: .report,
                format: .json,
                data: try DFTArtifactJSONEncoder().encode(scanImplementation)
            ),
            runID: runID
        )
        let faultUniverse = DFTFaultUniverse(
            name: "test-stuck-at",
            revision: "1",
            faults: [
                DFTFault(
                    id: "scan-out-sa1",
                    family: .stuckAt,
                    location: "scan_out",
                    stuckAtValue: .one
                ),
            ],
            declaredBy: "test"
        )
        let faultUniverseReference = try await store.store(
            DFTArtifactContent(
                artifactID: "replay-fault-universe",
                fileName: "fault-universe.json",
                kind: .input,
                format: .json,
                data: try DFTArtifactJSONEncoder().encode(faultUniverse)
            ),
            runID: runID
        )
        return DFTScanPatternReplayRequest(
            runID: runID,
            topModule: "scan_dut",
            patternArtifact: pattern,
            scanNetlistArtifact: netlist,
            scanImplementation: DFTScanImplementationReference(
                artifact: scanImplementationReference,
                transformedDesignDigest:
                    scanImplementation.transformedDesignDigest
            ),
            faultUniverseArtifact: faultUniverseReference,
            cellModelArtifacts: [model],
            preprocessorDefines: ["FUNCTIONAL"],
            faultIDs: ["scan-out-sa1"]
        )
    }

    private func scanImplementationFixture() -> DFTScanImplementation {
        DFTScanImplementation(
            architectureName: "test-scan",
            sourceDesignDigest: String(repeating: "1", count: 64),
            transformedDesignDigest: String(repeating: "2", count: 64),
            scanEnableSignal: "scan_en",
            scanEnableNetID: "scan-en-net",
            testModeSignal: "test_mode",
            testModeNetID: "test-mode-net",
            chains: [
                DFTRealizedScanChain(
                    chainID: "chain-0",
                    domainID: "clock-domain-0",
                    scanInSignal: "scan_in",
                    scanInNetID: "scan-in-net",
                    scanOutSignal: "scan_out",
                    scanOutNetID: "scan-out-net",
                    elements: [
                        DFTScanElementBinding(
                            position: 0,
                            cellID: "scan-cell-0",
                            instanceName: "u_scan_ff_0",
                            cellType: "scan_dff",
                            dataPinName: "D",
                            dataNetID: "data-net",
                            outputPinName: "Q",
                            outputNetID: "scan-out-net",
                            clockPinName: "CLK",
                            clockNetID: "clock-net",
                            scanInPinName: "SI",
                            scanInNetID: "scan-in-net",
                            scanEnablePinName: "SE",
                            scanEnableNetID: "scan-en-net",
                            testModePinName: "TM",
                            testModeNetID: "test-mode-net"
                        ),
                    ]
                ),
            ]
        )
    }

    private func provider(
        compiler: URL,
        simulator: URL,
        store: InMemoryDFTArtifactStore,
        compilerDigest: String? = nil,
        timeoutSeconds: Double = 5
    ) throws -> IcarusDFTScanPatternReplayProvider {
        IcarusDFTScanPatternReplayProvider(
            compilerDescriptor: DFTExternalToolDescriptor(
                engineID: "dft-pattern-replay",
                implementationID: "iverilog-test",
                implementationVersion: "test",
                binaryDigest: try compilerDigest ?? digest(compiler)
            ),
            compilerURL: compiler,
            simulatorDescriptor: DFTExternalToolDescriptor(
                engineID: "dft-pattern-replay",
                implementationID: "vvp-test",
                implementationVersion: "test",
                binaryDigest: try digest(simulator)
            ),
            simulatorURL: simulator,
            artifactReader: store,
            artifactStore: store,
            timeoutSeconds: timeoutSeconds,
            terminationGraceSeconds: 0.1
        )
    }

    private func fakeCompiler(in directory: URL) throws -> URL {
        try executable(
            named: "fake-iverilog",
            script: """
            #!/bin/sh
            output=''
            while [ "$#" -gt 0 ]; do
              if [ "$1" = '-o' ]; then
                shift
                output="$1"
              fi
              shift
            done
            if [ -z "$output" ]; then
              printf '%s\n' 'missing output path' >&2
              exit 2
            fi
            printf '%s\n' 'fake simulation image' > "$output"
            printf '%s\n' 'FAKE_IVERILOG_COMPLETE'
            """,
            in: directory
        )
    }

    private func fakeSimulator(in directory: URL) throws -> URL {
        try executable(
            named: "fake-vvp",
            script: """
            #!/bin/sh
            case "$*" in
              *+DFT_FAULT_INDEX=0*)
                printf '%s\n' 'DFT_REPLAY_RESULT index=0 mismatches=1'
                ;;
              *)
                printf '%s\n' 'DFT_REPLAY_GOLDEN_COMPLETE'
                ;;
            esac
            """,
            in: directory
        )
    }

    private func executable(
        named name: String,
        script: String,
        in directory: URL
    ) throws -> URL {
        let url = directory.appending(path: name)
        try Data((script + "\n").utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }

    private func digest(_ url: URL) throws -> String {
        try SHA256ContentDigester()
            .digest(data: Data(contentsOf: url, options: .mappedIfSafe))
            .hexadecimalValue
    }

    private func patternFixture() throws -> Data {
        let url = try #require(
            Bundle.module.url(
                forResource: "pattern-exchange",
                withExtension: "stil",
                subdirectory: "Fixtures"
            )
        )
        return try Data(contentsOf: url)
    }

    private func providerPatternFixture() throws -> Data {
        var program = try STILPatternCodec().decode(patternFixture())
        program.signals.insert(
            DFTPatternSignal(name: "scan_en", direction: .input),
            at: 2
        )
        program.signals.insert(
            DFTPatternSignal(name: "test_mode", direction: .input),
            at: 3
        )
        guard let inputWaveform = program.timingSets[0].waveforms.first(
            where: { $0.signalName == "scan_in" }
        ) else {
            throw DFTScanPatternReplayError.harnessGenerationFailed(
                "test fixture is missing its input waveform"
            )
        }
        var scanEnableWaveform = inputWaveform
        scanEnableWaveform.signalName = "scan_en"
        var testModeWaveform = inputWaveform
        testModeWaveform.signalName = "test_mode"
        program.timingSets[0].waveforms.insert(scanEnableWaveform, at: 2)
        program.timingSets[0].waveforms.insert(testModeWaveform, at: 3)
        for procedureIndex in program.procedures.indices {
            for cycleIndex in program.procedures[procedureIndex].cycles.indices {
                program.procedures[procedureIndex].cycles[cycleIndex]
                    .assignments.append(
                        DFTPatternAssignment(
                            target: "scan_en",
                            symbols: "1"
                        )
                    )
                program.procedures[procedureIndex].cycles[cycleIndex]
                    .assignments.append(
                        DFTPatternAssignment(
                            target: "test_mode",
                            symbols: "1"
                        )
                    )
            }
        }
        return try STILPatternCodec().encode(program)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(
                path: "dft-replay-tests-\(UUID().uuidString)",
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
            Issue.record("Failed to remove temporary test directory: \(error)")
        }
    }
}
