import CircuiteFoundation
@testable import DFTCLIKit
import DFTCore
import DFTExternalTools
import DFTPatternExchange
import Foundation
import Testing

@Suite("DFT CLI replay")
struct DFTCLIReplayTests {
    @Test("replay command reaches the retained-artifact Icarus provider")
    func replaysRetainedArtifacts() async throws {
        let root = try temporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let compiler = try fakeCompiler(in: root)
        let simulator = try fakeSimulator(in: root)
        let store = FileSystemDFTArtifactStore(rootURL: root)
        let request = try await replayRequest(store: store)
        let requestURL = root.appending(path: "replay-request.json")
        let compilerDescriptorURL = root.appending(path: "compiler.json")
        let simulatorDescriptorURL = root.appending(path: "simulator.json")
        let resultURL = root.appending(path: "replay-result.json")
        try DFTArtifactJSONEncoder().encode(request).write(
            to: requestURL,
            options: .atomic
        )
        try descriptor(
            implementationID: "iverilog-cli-test",
            executable: compiler
        ).write(to: compilerDescriptorURL)
        try descriptor(
            implementationID: "vvp-cli-test",
            executable: simulator
        ).write(to: simulatorDescriptorURL)
        let writer = RecordingDFTCLIOutputWriter()

        let exitCode = try await DFTCLICommand(outputWriter: writer).run(
            arguments: [
                "replay",
                "--request", requestURL.path,
                "--output-dir", root.path,
                "--compiler", compiler.path,
                "--compiler-descriptor", compilerDescriptorURL.path,
                "--simulator", simulator.path,
                "--simulator-descriptor", simulatorDescriptorURL.path,
                "--timeout-seconds", "5",
                "--termination-grace-seconds", "0.1",
                "--result", resultURL.path,
            ]
        )

        #expect(exitCode == 0)
        #expect(writer.output.isEmpty)
        #expect(writer.errors.isEmpty)
        let result = try JSONDecoder().decode(
            DFTScanPatternReplayResult.self,
            from: Data(contentsOf: resultURL)
        )
        #expect(result.runID == request.runID)
        #expect(result.observations == [
            DFTScanPatternReplayObservation(
                faultID: "scan-out-sa1",
                detected: true,
                mismatchCount: 1
            ),
        ])
        #expect(result.artifacts.count == 3)
        for artifact in result.artifacts {
            #expect(try await !store.data(for: artifact).isEmpty)
        }
    }

    @Test("replay command rejects a mismatched compiler descriptor")
    func rejectsCompilerIdentityMismatch() async throws {
        let root = try temporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let compiler = try fakeCompiler(in: root)
        let simulator = try fakeSimulator(in: root)
        let store = FileSystemDFTArtifactStore(rootURL: root)
        let request = try await replayRequest(store: store)
        let requestURL = root.appending(path: "replay-request.json")
        let compilerDescriptorURL = root.appending(path: "compiler.json")
        let simulatorDescriptorURL = root.appending(path: "simulator.json")
        try DFTArtifactJSONEncoder().encode(request).write(
            to: requestURL,
            options: .atomic
        )
        let mismatched = DFTExternalToolDescriptor(
            engineID: "dft-pattern-replay",
            implementationID: "iverilog-cli-test",
            implementationVersion: "test",
            binaryDigest: String(repeating: "0", count: 64)
        )
        try DFTArtifactJSONEncoder().encode(mismatched).write(
            to: compilerDescriptorURL,
            options: .atomic
        )
        try descriptor(
            implementationID: "vvp-cli-test",
            executable: simulator
        ).write(to: simulatorDescriptorURL)

        await #expect(throws: DFTScanPatternReplayError.self) {
            _ = try await DFTCLICommand().run(
                arguments: [
                    "replay",
                    "--request", requestURL.path,
                    "--output-dir", root.path,
                    "--compiler", compiler.path,
                    "--compiler-descriptor", compilerDescriptorURL.path,
                    "--simulator", simulator.path,
                    "--simulator-descriptor", simulatorDescriptorURL.path,
                ]
            )
        }
    }

    private func replayRequest(
        store: FileSystemDFTArtifactStore
    ) async throws -> DFTScanPatternReplayRequest {
        let runID = "icarus-cli-replay-test"
        let pattern = try await store.store(
            DFTArtifactContent(
                artifactID: "cli-replay-pattern",
                fileName: "pattern.stil",
                kind: .testPattern,
                format: .stil,
                data: try patternFixture()
            ),
            runID: runID
        )
        let netlist = try await store.store(
            DFTArtifactContent(
                artifactID: "cli-replay-netlist",
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
                artifactID: "cli-replay-cell-model",
                fileName: "cell-model.v",
                kind: .model,
                format: .verilog,
                data: Data("module unused_cell_model; endmodule\n".utf8)
            ),
            runID: runID
        )
        let implementation = scanImplementation()
        let implementationArtifact = try await store.store(
            DFTArtifactContent(
                artifactID: "cli-scan-implementation",
                fileName: "scan-implementation.json",
                kind: .report,
                format: .json,
                data: try DFTArtifactJSONEncoder().encode(implementation)
            ),
            runID: runID
        )
        let universe = DFTFaultUniverse(
            name: "cli-stuck-at",
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
        let universeArtifact = try await store.store(
            DFTArtifactContent(
                artifactID: "cli-fault-universe",
                fileName: "fault-universe.json",
                kind: .input,
                format: .json,
                data: try DFTArtifactJSONEncoder().encode(universe)
            ),
            runID: runID
        )
        return DFTScanPatternReplayRequest(
            runID: runID,
            topModule: "scan_dut",
            patternArtifact: pattern,
            scanNetlistArtifact: netlist,
            scanImplementation: DFTScanImplementationReference(
                artifact: implementationArtifact,
                transformedDesignDigest: implementation.transformedDesignDigest
            ),
            faultUniverseArtifact: universeArtifact,
            cellModelArtifacts: [model],
            preprocessorDefines: ["FUNCTIONAL"],
            faultIDs: ["scan-out-sa1"]
        )
    }

    private func scanImplementation() -> DFTScanImplementation {
        DFTScanImplementation(
            architectureName: "cli-scan",
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

    private func patternFixture() throws -> Data {
        guard let fixtureURL = Bundle.module.url(
            forResource: "pattern-exchange",
            withExtension: "stil",
            subdirectory: "Fixtures"
        ) else {
            throw DFTCLIReplayTestError.fixtureMissing
        }
        var program = try STILPatternCodec().decode(
            Data(contentsOf: fixtureURL)
        )
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
            throw DFTCLIReplayTestError.fixtureMissing
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
                        DFTPatternAssignment(target: "scan_en", symbols: "1")
                    )
                program.procedures[procedureIndex].cycles[cycleIndex]
                    .assignments.append(
                        DFTPatternAssignment(target: "test_mode", symbols: "1")
                    )
            }
        }
        return try STILPatternCodec().encode(program)
    }

    private func descriptor(
        implementationID: String,
        executable: URL
    ) throws -> Data {
        try DFTArtifactJSONEncoder().encode(
            DFTExternalToolDescriptor(
                engineID: "dft-pattern-replay",
                implementationID: implementationID,
                implementationVersion: "test",
                binaryDigest: try digest(executable)
            )
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
              exit 2
            fi
            printf '%s\n' 'fake simulation image' > "$output"
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

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "dft-cli-replay-tests-\(UUID().uuidString)",
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
            Issue.record("Failed to remove CLI test directory: \(error)")
        }
    }
}

private enum DFTCLIReplayTestError: Error {
    case fixtureMissing
}
