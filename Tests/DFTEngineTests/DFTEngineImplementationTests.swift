import ATPGEngine
import BISTEngine
import CircuiteFoundation
import DFTCore
import DFTEngine
import Foundation
import LogicIR
import PDKCore
import ScanInsertion
import Testing
import TimingCore

@Suite("DFTEngine implementation")
struct DFTEngineImplementationTests {
    @Test("scan planner distributes elements and insertion emits provenance")
    func scanInsertion() async throws {
        let store = InMemoryDFTArtifactStore()
        let sourceSnapshot = makeGateSnapshot(sequentialCellCount: 5)
        let sourceDigest = try LogicDesignSnapshotCodec.digest(sourceSnapshot)
        let libraryManifest = makeCellLibraryManifest()
        let libraryReference = try makeCellLibraryReference(manifest: libraryManifest)
        let request = makeRequest(
            operation: .scanInsertion,
            designDigest: sourceDigest,
            cellLibrary: libraryReference,
            scanArchitecture: DFTScanArchitecture(
                name: "core-scan",
                clocks: [DFTScanClock(id: "clk", signalName: "scan_clk", periodNanoseconds: 10)],
                domains: [DFTScanDomain(id: "core", clockID: "clk", chainCount: 2, estimatedElementCount: 5)],
                scanEnableSignal: "scan_en",
                testModeSignal: "test_mode"
            ),
            insertionPolicy: DFTScanInsertionPolicy(scanCellName: "SDFF")
        )

        let result = try await DeterministicScanInsertionEngine(
            artifactStore: store,
            designLoader: InMemoryDFTDesignLoader(snapshot: sourceSnapshot),
            cellLibraryLoader: InMemoryDFTCellLibraryLoader(manifest: libraryManifest)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.scanPlan?.chains.map(\.estimatedElementCount) == [3, 2])
        #expect(result.artifacts.contains { $0 == result.payload.transformedDesign?.artifact })
        #expect(result.payload.transformedDesign?.provenance?.sourceDesignDigest == sourceDigest)
        #expect(result.payload.transformedDesign?.provenance?.transformationID == "dft-scan-insertion")
        #expect(result.payload.designDiff?.changes.count == 7)
        #expect(result.artifacts.count == 2)
        #expect(await store.data(for: "dft/runs/run-scanInsertion/design-diff.json") != nil)
        let transformedData = try #require(await store.data(for: "dft/runs/run-scanInsertion/transformed-design.json"))
        let transformedSnapshot = try LogicDesignSnapshotCodec.decode(transformedData)
        let transformedCells = try #require(transformedSnapshot.gate?.modules.first?.cells)
        #expect(transformedCells.filter { $0.type == "SDFF" }.count == 5)
        #expect(transformedCells.filter { $0.type == "DFT_SCAN_OUT" }.count == 2)
    }

    @Test("scan insertion blocks without a canonical design loader")
    func scanInsertionRequiresCanonicalDesign() async throws {
        let request = makeRequest(
            operation: .scanInsertion,
            cellLibrary: try makeCellLibraryReference(manifest: makeCellLibraryManifest()),
            scanArchitecture: scanArchitecture(),
            insertionPolicy: DFTScanInsertionPolicy(scanCellName: "SDFF")
        )

        let libraryManifest = makeCellLibraryManifest()
        let result = try await DeterministicScanInsertionEngine(
            cellLibraryLoader: InMemoryDFTCellLibraryLoader(manifest: libraryManifest)
        ).execute(request)

        #expect(result.status == .blocked)
        #expect(result.dftDiagnostics.contains { $0.code == "DFT_DESIGN_LOADER_MISSING" })
    }

    @Test("scan insertion blocks when clock connectivity is ambiguous")
    func scanInsertionRequiresClockBinding() async throws {
        let sourceSnapshot = makeGateSnapshot(sequentialCellCount: 2)
        let sourceDigest = try LogicDesignSnapshotCodec.digest(sourceSnapshot)
        let libraryManifest = makeCellLibraryManifest()
        let libraryReference = try makeCellLibraryReference(manifest: libraryManifest)
        var architecture = scanArchitecture()
        architecture.clocks[0].signalName = "unbound_clock"
        architecture.domains[0].estimatedElementCount = 2
        let request = makeRequest(
            operation: .scanInsertion,
            designDigest: sourceDigest,
            cellLibrary: libraryReference,
            scanArchitecture: architecture,
            insertionPolicy: DFTScanInsertionPolicy(scanCellName: "SDFF")
        )

        let result = try await DeterministicScanInsertionEngine(
            designLoader: InMemoryDFTDesignLoader(snapshot: sourceSnapshot),
            cellLibraryLoader: InMemoryDFTCellLibraryLoader(manifest: libraryManifest)
        ).execute(request)

        #expect(result.status == .blocked)
        #expect(result.dftDiagnostics.contains { $0.code == "DFT_GATE_LEVEL_TRANSFORM_FAILED" })
        #expect(result.dftDiagnostics.contains { $0.message.contains("clock") })
    }

    @Test("scan insertion blocks a cell library bound to another PDK")
    func scanInsertionRequiresMatchingCellLibraryPDK() async throws {
        let sourceSnapshot = makeGateSnapshot(sequentialCellCount: 1)
        let sourceDigest = try LogicDesignSnapshotCodec.digest(sourceSnapshot)
        var mismatchedManifest = makeCellLibraryManifest()
        mismatchedManifest.pdkDigest = String(repeating: "f", count: 64)
        let libraryReference = try makeCellLibraryReference(manifest: mismatchedManifest)
        let request = makeRequest(
            operation: .scanInsertion,
            designDigest: sourceDigest,
            cellLibrary: libraryReference,
            scanArchitecture: scanArchitecture(),
            insertionPolicy: DFTScanInsertionPolicy(scanCellName: "SDFF")
        )

        let result = try await DeterministicScanInsertionEngine(
            designLoader: InMemoryDFTDesignLoader(snapshot: sourceSnapshot),
            cellLibraryLoader: InMemoryDFTCellLibraryLoader(manifest: mismatchedManifest)
        ).execute(request)

        #expect(result.status == .blocked)
        #expect(result.dftDiagnostics.contains { $0.code == "DFT_CELL_LIBRARY_LOAD_FAILED" })
        #expect(result.dftDiagnostics.contains { $0.message.contains("pdkDigest") })
    }

    @Test("ATPG reports declared coverage and is deterministic")
    func atpgCoverage() async throws {
        let store = InMemoryDFTArtifactStore()
        let universe = DFTFaultUniverse(
            name: "smoke-faults",
            revision: "r1",
            faults: [
                DFTFault(id: "n1-sa0", family: .stuckAt, location: "n1", polarity: .activeLow, stuckAtValue: .zero),
                DFTFault(id: "n2-transition", family: .transition, location: "n2")
            ],
            declaredBy: "fixture"
        )
        let request = makeRequest(
            operation: .atpg,
            scanArchitecture: scanArchitecture(),
            faultUniverse: universe,
            atpgConfiguration: DFTATPGConfiguration(patternLength: 8, randomSeed: 42)
        )
        let engine = DeterministicATPGEngine(artifactStore: store)

        let first = try await engine.execute(request)
        let second = try await engine.execute(request)

        #expect(first.status == .blocked)
        #expect(first.payload.faultCoverage == nil)
        #expect(first.payload.coverageEvidence?.detectedFaultCount == 1)
        #expect(first.payload.coverageEvidence?.abortedFaultCount == 1)
        #expect(first.dftDiagnostics.contains { $0.code == "DFT_FAULT_SEMANTICS_UNAVAILABLE" })
        #expect(first.payload.patterns?.patterns == second.payload.patterns?.patterns)
        #expect(
            first.artifacts.map(\.digest.hexadecimalValue)
                == second.artifacts.map(\.digest.hexadecimalValue)
        )
    }

    @Test("gate-level ATPG extracts and detects combinational stuck-at faults")
    func gateLevelATPG() async throws {
        let snapshot = makeCombinationalSnapshot()
        let designDigest = try LogicDesignSnapshotCodec.digest(snapshot)
        let request = makeRequest(
            operation: .atpg,
            designDigest: designDigest,
            scanArchitecture: scanArchitecture(),
            atpgConfiguration: DFTATPGConfiguration(
                patternLength: 2,
                faultSource: .gateLevel
            )
        )
        let result = try await DeterministicATPGEngine(
            designLoader: InMemoryDFTDesignLoader(snapshot: snapshot)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.faultCoverage == 1)
        #expect(result.payload.coverageEvidence?.declaredFaultCount == 4)
        #expect(result.payload.coverageEvidence?.detectedFaultCount == 4)
        #expect(result.payload.patterns?.patterns.count == 4)
        #expect(result.payload.patterns?.patterns.allSatisfy { $0.bits.count == 2 } == true)
        #expect(result.dftDiagnostics.contains { $0.code == "DFT_GATE_LEVEL_ATPG_COMPLETED" })
    }

    @Test("bounded gate-level ATPG simulates DFF state transitions")
    func boundedSequentialATPG() async throws {
        let snapshot = makeSequentialAtpgSnapshot()
        let designDigest = try LogicDesignSnapshotCodec.digest(snapshot)
        let request = makeRequest(
            operation: .atpg,
            designDigest: designDigest,
            scanArchitecture: scanArchitecture(),
            atpgConfiguration: DFTATPGConfiguration(
                patternLength: 4,
                faultSource: .gateLevel,
                maximumExhaustiveInputCount: 4,
                maximumSequentialCycleCount: 2
            )
        )

        let result = try await DeterministicATPGEngine(
            designLoader: InMemoryDFTDesignLoader(snapshot: snapshot)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.faultCoverage == 1)
        #expect(result.payload.coverageEvidence?.declaredFaultCount == 2)
        #expect(result.payload.coverageEvidence?.detectedFaultCount == 2)
        #expect(result.dftDiagnostics.contains { $0.code == "DFT_GATE_LEVEL_SEQUENTIAL_ATPG_COMPLETED" })
    }

    @Test("bounded sequential simulation models scan shift and functional capture")
    func boundedScanCapture() throws {
        let snapshot = LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top"),
            gate: GateDesign(
                topModuleName: "top",
                modules: [GateModule(
                    id: "module-top",
                    name: "top",
                    ports: [
                        RTLPort(id: "port-scan-in", name: "scan_in", direction: .input),
                        RTLPort(id: "port-scan-en", name: "scan_en", direction: .input),
                        RTLPort(id: "port-clk", name: "scan_clk", direction: .input),
                        RTLPort(id: "port-d", name: "d", direction: .input),
                        RTLPort(id: "port-q", name: "q", direction: .output),
                    ],
                    cells: [GateCell(
                        id: "cell-sdff",
                        type: "SDFF",
                        instanceName: "u_sdff",
                        pins: [
                            GatePin(id: "sdff-d", name: "D", direction: .input, netID: "net-d"),
                            GatePin(id: "sdff-si", name: "SI", direction: .input, netID: "net-scan-in"),
                            GatePin(id: "sdff-se", name: "SE", direction: .input, netID: "net-scan-en"),
                            GatePin(id: "sdff-clk", name: "CLK", direction: .input, netID: "net-clk"),
                            GatePin(id: "sdff-q", name: "Q", direction: .output, netID: "net-q"),
                        ]
                    )],
                    nets: [
                        GateNet(id: "net-d", name: "d"),
                        GateNet(id: "net-scan-in", name: "scan_in"),
                        GateNet(id: "net-scan-en", name: "scan_en"),
                        GateNet(id: "net-clk", name: "scan_clk"),
                        GateNet(id: "net-q", name: "q"),
                    ]
                )]
            )
        )

        let result = try GateLevelSequentialSimulator().simulate(
            snapshot: snapshot,
            inputCycles: [
                ["scan_in": true, "scan_en": true, "scan_clk": false, "d": false],
                ["scan_in": true, "scan_en": true, "scan_clk": true, "d": false],
                ["scan_in": false, "scan_en": false, "scan_clk": false, "d": false],
                ["scan_in": false, "scan_en": false, "scan_clk": true, "d": false],
                ["scan_in": false, "scan_en": false, "scan_clk": false, "d": false],
            ],
            initialState: ["net-q": false]
        )

        #expect(result.observedValues[2]["q"] == true)
        #expect(result.observedValues[4]["q"] == false)
        #expect(result.finalState["net-q"] == false)
    }

    @Test("bounded sequential simulation applies qualified asynchronous reset and set semantics")
    func boundedSequentialControlSemantics() throws {
        let snapshot = makeControlledSequentialSnapshot()
        let contract = DFTSequentialCellContract(
            cellTypes: ["DFFRS"],
            clockPinNames: ["CLK"],
            resetPinNames: ["RESET_N"],
            resetPolarity: .activeLow,
            setPinNames: ["SET"],
            setPolarity: .activeHigh,
            controlTiming: .asynchronous,
            clockEdge: .rising
        )

        let result = try GateLevelSequentialSimulator().simulate(
            snapshot: snapshot,
            inputCycles: [
                ["d": false, "clk": false, "reset_n": false, "set": false],
                ["d": false, "clk": false, "reset_n": true, "set": true],
                ["d": true, "clk": true, "reset_n": true, "set": false],
                ["d": false, "clk": false, "reset_n": true, "set": false],
                ["d": false, "clk": true, "reset_n": true, "set": false],
                ["d": false, "clk": false, "reset_n": true, "set": false],
            ],
            initialState: ["net-q": false],
            sequentialContracts: [contract]
        )

        #expect(result.observedValues.map { $0["q"] } == [false, true, true, true, true, false])
        #expect(result.finalState["net-q"] == false)
    }

    @Test("sequential control pins are blocked without an explicit cell contract")
    func sequentialControlContractIsRequired() throws {
        let snapshot = makeControlledSequentialSnapshot(cellType: "DFF")

        do {
            _ = try GateLevelSequentialSimulator().simulate(
                snapshot: snapshot,
                inputCycles: [["d": false, "clk": false, "reset_n": false, "set": false]],
                initialState: ["net-q": false]
            )
            Issue.record("A sequential control pin without a contract must be rejected.")
        } catch let error as GateLevelSimulationError {
            #expect(error == .sequentialControlContractMissing(instance: "u_ff", type: "DFF"))
        }
    }

    @Test("bounded sequential simulation applies synchronous controls on the declared falling edge")
    func boundedSynchronousControlSemantics() throws {
        let contract = DFTSequentialCellContract(
            cellTypes: ["DFFRS"],
            clockPinNames: ["CLK"],
            resetPinNames: ["RESET_N"],
            resetPolarity: .activeLow,
            setPinNames: ["SET"],
            setPolarity: .activeHigh,
            controlTiming: .synchronous,
            clockEdge: .falling
        )

        let result = try GateLevelSequentialSimulator().simulate(
            snapshot: makeControlledSequentialSnapshot(),
            inputCycles: [
                ["d": false, "clk": true, "reset_n": true, "set": false],
                ["d": false, "clk": false, "reset_n": true, "set": true],
                ["d": false, "clk": true, "reset_n": true, "set": false],
                ["d": false, "clk": false, "reset_n": true, "set": false],
                ["d": false, "clk": true, "reset_n": true, "set": false],
            ],
            initialState: ["net-q": false],
            sequentialContracts: [contract]
        )

        #expect(result.observedValues.map { $0["q"] } == [false, false, true, true, false])
        #expect(result.finalState["net-q"] == false)
    }

    @Test("bounded sequential simulation models a qualified level-sensitive latch")
    func boundedLatchSemantics() throws {
        let contract = DFTSequentialCellContract(
            cellTypes: ["LATCH"],
            clockPinNames: ["EN"],
            elementKind: .levelSensitive,
            latchEnablePolarity: .activeHigh
        )

        let result = try GateLevelSequentialSimulator().simulate(
            snapshot: makeLatchSnapshot(),
            inputCycles: [
                ["d": false, "en": false],
                ["d": true, "en": true],
                ["d": false, "en": true],
                ["d": true, "en": false],
                ["d": true, "en": true],
                ["d": false, "en": false],
            ],
            initialState: ["net-q": false],
            sequentialContracts: [contract]
        )

        #expect(result.observedValues.map { $0["q"] } == [false, false, true, false, false, true])
        #expect(result.finalState["net-q"] == true)
    }

    @Test("sequential element contracts round-trip with latch semantics")
    func sequentialContractRoundTrip() throws {
        let configuration = DFTATPGConfiguration(
            sequentialCellContracts: [DFTSequentialCellContract(
                cellTypes: ["LATCH"],
                clockPinNames: ["EN"],
                elementKind: .levelSensitive,
                latchEnablePolarity: .activeLow
            )]
        )
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(DFTATPGConfiguration.self, from: data)

        #expect(decoded == configuration)
    }

    @Test("latches are blocked without a level-sensitive element contract")
    func latchContractIsRequired() throws {
        do {
            _ = try GateLevelSequentialSimulator().simulate(
                snapshot: makeLatchSnapshot(),
                inputCycles: [["d": false, "en": false]],
                initialState: ["net-q": false]
            )
            Issue.record("A latch without an explicit element contract must be rejected.")
        } catch let error as GateLevelSimulationError {
            #expect(error == .sequentialElementContractMissing(instance: "u_latch", type: "LATCH"))
        }
    }

    @Test("bounded ATPG simulates combinational transition faults with two vectors")
    func boundedTransitionATPG() async throws {
        let snapshot = makeCombinationalSnapshot()
        let designDigest = try LogicDesignSnapshotCodec.digest(snapshot)
        let request = makeRequest(
            operation: .atpg,
            designDigest: designDigest,
            scanArchitecture: scanArchitecture(),
            faultUniverse: DFTFaultUniverse(
                name: "transition-faults",
                revision: "r1",
                faults: [DFTFault(
                    id: "top-y-slow-rise",
                    family: .transition,
                    location: "top.y",
                    transitionDirection: .slowToRise
                )],
                declaredBy: "fixture"
            ),
            atpgConfiguration: DFTATPGConfiguration(
                patternLength: 4,
                maximumExhaustiveInputCount: 4
            )
        )

        let result = try await DeterministicATPGEngine(
            designLoader: InMemoryDFTDesignLoader(snapshot: snapshot)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.faultCoverage == 1)
        #expect(result.payload.coverageEvidence?.detectedFaultCount == 1)
        #expect(result.payload.coverageEvidence?.outcomes.first?.status == .detected)
    }

    @Test("bounded ATPG models transition faults through a qualified sequential cell")
    func boundedSequentialTransitionATPG() async throws {
        let snapshot = makeControlledSequentialSnapshot()
        let designDigest = try LogicDesignSnapshotCodec.digest(snapshot)
        let request = makeRequest(
            operation: .atpg,
            designDigest: designDigest,
            scanArchitecture: scanArchitecture(),
            faultUniverse: DFTFaultUniverse(
                name: "sequential-transition-faults",
                revision: "r1",
                faults: [DFTFault(
                    id: "q-slow-rise",
                    family: .transition,
                    location: "q",
                    transitionDirection: .slowToRise
                )],
                declaredBy: "fixture"
            ),
            atpgConfiguration: DFTATPGConfiguration(
                patternLength: 8,
                maximumExhaustiveInputCount: 8,
                sequentialCellContracts: [DFTSequentialCellContract(
                    cellTypes: ["DFFRS"],
                    resetPinNames: ["RESET_N"],
                    resetPolarity: .activeLow,
                    setPinNames: ["SET"],
                    setPolarity: .activeHigh
                )]
            )
        )

        let result = try await DeterministicATPGEngine(
            designLoader: InMemoryDFTDesignLoader(snapshot: snapshot)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.faultCoverage == 1)
        #expect(result.payload.coverageEvidence?.detectedFaultCount == 1)
        #expect(result.payload.coverageEvidence?.outcomes.first?.status == .detected)
    }

    @Test("ATPG derives sequential semantics from the process-scoped cell library")
    func atpgLoadsCellLibrarySequentialContract() async throws {
        let snapshot = makeControlledSequentialSnapshot()
        let manifest = DFTCellLibraryManifest(
            processID: "test-process",
            version: "1",
            pdkDigest: String(repeating: "e", count: 64),
            bindings: [DFTCellLibraryBinding(
                bindingID: "dffrs-to-sdffrs",
                functionalCellType: "DFFRS",
                scanCellType: "SDFFRS",
                dataPinName: "D",
                outputPinName: "Q",
                clockPinNames: ["CLK"],
                resetPinNames: ["RESET_N"],
                resetPolarity: .activeLow,
                setPinNames: ["SET"],
                setPolarity: .activeHigh,
                controlTiming: .asynchronous,
                clockEdge: .rising,
                scanInPinName: "SI",
                scanEnablePinName: "SE"
            )],
            evidenceProvenance: DFTEvidenceProvenance(
                status: .corpusObserved,
                corpusRevision: "fixture-m3"
            )
        )
        let request = makeRequest(
            operation: .atpg,
            designDigest: try LogicDesignSnapshotCodec.digest(snapshot),
            cellLibrary: try makeCellLibraryReference(manifest: manifest),
            scanArchitecture: scanArchitecture(),
            atpgConfiguration: DFTATPGConfiguration(
                patternLength: 8,
                faultSource: .gateLevel,
                maximumExhaustiveInputCount: 8,
                maximumSequentialCycleCount: 2
            )
        )

        let result = try await DeterministicATPGEngine(
            designLoader: InMemoryDFTDesignLoader(snapshot: snapshot),
            cellLibraryLoader: InMemoryDFTCellLibraryLoader(manifest: manifest)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.faultCoverage == 1)
        #expect(result.payload.coverageEvidence?.detectedFaultCount == 2)
        #expect(result.dftDiagnostics.contains { $0.code == "DFT_GATE_LEVEL_SEQUENTIAL_ATPG_COMPLETED" })
    }

    @Test("gate-level ATPG blocks unsupported sequential cell semantics")
    func gateLevelATPGBlocksSequentialCells() async throws {
        let snapshot = makeGateSnapshot(sequentialCellCount: 1)
        let designDigest = try LogicDesignSnapshotCodec.digest(snapshot)
        let request = makeRequest(
            operation: .atpg,
            designDigest: designDigest,
            scanArchitecture: scanArchitecture(),
            atpgConfiguration: DFTATPGConfiguration(
                patternLength: 1,
                faultSource: .gateLevel
            )
        )

        let result = try await DeterministicATPGEngine(
            designLoader: InMemoryDFTDesignLoader(snapshot: snapshot)
        ).execute(request)

        #expect(result.status == .blocked)
        #expect(result.payload.faultCoverage == nil)
        #expect(result.dftDiagnostics.contains { $0.code == "DFT_GATE_LEVEL_ATPG_BLOCKED" })
        #expect(result.dftDiagnostics.contains { $0.message.contains("sequential") })
    }

    @Test("ATPG blocks when the fault universe is absent")
    func atpgMissingUniverse() async throws {
        let request = makeRequest(
            operation: .atpg,
            scanArchitecture: scanArchitecture(),
            atpgConfiguration: DFTATPGConfiguration()
        )

        let result = try await DeterministicATPGEngine().execute(request)

        #expect(result.status == .blocked)
        #expect(result.payload.faultCoverage == nil)
        #expect(result.dftDiagnostics.contains { $0.code == "DFT_FAULT_UNIVERSE_MISSING" })
    }

    @Test("process-specific ATPG semantics remain blocked")
    func processSpecificFaultsAreNotPassed() async throws {
        let universe = DFTFaultUniverse(
            name: "process-faults",
            revision: "r1",
            faults: [DFTFault(
                id: "m1-leakage",
                family: .processSpecific,
                location: "m1",
                processFamily: "leakage"
            )],
            declaredBy: "fixture"
        )
        let request = makeRequest(
            operation: .atpg,
            scanArchitecture: scanArchitecture(),
            faultUniverse: universe,
            atpgConfiguration: DFTATPGConfiguration()
        )

        let result = try await DeterministicATPGEngine().execute(request)

        #expect(result.status == .blocked)
        #expect(result.payload.faultCoverage == nil)
        #expect(result.dftDiagnostics.contains { $0.code == "DFT_PROCESS_FAULT_FAMILY_UNDECLARED" })
    }

    @Test("declared process-specific ATPG faults remain blocked without an injected model")
    func declaredProcessSpecificFaultsRequireModel() async throws {
        let universe = DFTFaultUniverse(
            name: "process-faults",
            revision: "r1",
            faults: [DFTFault(
                id: "m1-leakage",
                family: .processSpecific,
                location: "m1",
                processFamily: "leakage"
            )],
            declaredBy: "fixture"
        )
        let request = makeRequest(
            operation: .atpg,
            scanArchitecture: scanArchitecture(),
            faultUniverse: universe,
            atpgConfiguration: DFTATPGConfiguration(
                patternLength: 8,
                supportedProcessFamilies: ["leakage"]
            )
        )

        let result = try await DeterministicATPGEngine().execute(request)

        #expect(result.status == .blocked)
        #expect(result.payload.faultCoverage == nil)
        #expect(result.dftDiagnostics.contains { $0.code == "DFT_PROCESS_FAULT_MODEL_MISSING" })
    }

    @Test("process-specific ATPG requires an injected model and preserves smoke evidence")
    func processSpecificFaultModelIsExplicit() async throws {
        let universe = DFTFaultUniverse(
            name: "process-faults",
            revision: "r1",
            faults: [DFTFault(
                id: "m1-leakage",
                family: .processSpecific,
                location: "m1",
                processFamily: "leakage"
            )],
            declaredBy: "fixture"
        )
        let request = makeRequest(
            operation: .atpg,
            scanArchitecture: scanArchitecture(),
            faultUniverse: universe,
            atpgConfiguration: DFTATPGConfiguration(
                patternLength: 8,
                supportedProcessFamilies: ["leakage"]
            )
        )

        let result = try await DeterministicATPGEngine(
            processFaultModel: ProcessSpecificFaultModelFixture()
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.faultCoverage == 1)
        #expect(result.payload.patterns?.patterns.first?.bits == "11111111")
        #expect(result.payload.coverageEvidence?.outcomes.first?.modelID == "fixture-process-fault-model")
        #expect(result.payload.evidenceProvenance.status == .smokeObserved)
        #expect(result.dftDiagnostics.contains { $0.code == "DFT_ATPG_COMPLETED" })
    }

    @Test("ATPG records untestable faults without claiming coverage")
    func untestableFaultsAreExplicit() async throws {
        let request = makeRequest(
            operation: .atpg,
            scanArchitecture: scanArchitecture(),
            faultUniverse: DFTFaultUniverse(
                name: "incomplete-faults",
                revision: "r1",
                faults: [DFTFault(id: "unknown-site", family: .stuckAt, location: "")],
                declaredBy: "fixture"
            ),
            atpgConfiguration: DFTATPGConfiguration()
        )

        let result = try await DeterministicATPGEngine().execute(request)

        #expect(result.status == .blocked)
        #expect(result.payload.faultCoverage == nil)
        #expect(result.payload.coverageEvidence?.untestableFaultCount == 1)
        #expect(result.payload.coverageEvidence?.outcomes.first?.status == .untestable)
    }

    @Test("BIST emits a transformed design and diff")
    func bistInsertion() async throws {
        let store = InMemoryDFTArtifactStore()
        let sourceSnapshot = makeGateSnapshot(sequentialCellCount: 1)
        let sourceDigest = try LogicDesignSnapshotCodec.digest(sourceSnapshot)
        let request = makeRequest(
            operation: .bist,
            testIntent: DFTTestIntent(
                name: "production-test",
                modes: ["bist"],
                testModeSignal: "test_mode",
                scanEnableSignal: "scan_en"
            ),
            designDigest: sourceDigest,
            bistConfiguration: DFTBISTConfiguration(
                name: "logic-bist",
                kind: .logic,
                controllerCellName: "LBIST_CTRL",
                targetInstances: ["u_core"],
                patternCount: 128,
                signatureRegisterName: "misr_q",
                clockSignal: "scan_clk",
                targetBindings: [DFTBISTTargetBinding(
                    instanceName: "u_ff0",
                    patternInputPinNames: ["D"],
                    responseOutputPinNames: ["Q"]
                )]
            )
        )

        let result = try await DeterministicBISTEngine(
            artifactStore: store,
            designLoader: InMemoryDFTDesignLoader(snapshot: sourceSnapshot)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.bistStructure?.name == "logic-bist")
        #expect(result.payload.designDiff?.changes.count ?? 0 > 1)
        #expect(result.artifacts.count == 3)
        #expect(result.payload.transformedDesign?.provenance?.sourceDesignDigest == sourceDigest)
        #expect(result.payload.transformedDesign?.provenance?.transformationID == "dft-bist-insertion")
        let transformedData = try #require(await store.data(for: "dft/runs/run-bist/bist-transformed-design.json"))
        let transformedSnapshot = try LogicDesignSnapshotCodec.decode(transformedData)
        let transformedCells = try #require(transformedSnapshot.gate?.modules.first?.cells)
        #expect(transformedCells.contains { $0.type == "DFT_BIST_INPUT_MUX" })
        #expect(transformedCells.contains { $0.type == "DFT_BIST_RESPONSE_COMPACTOR" })
        #expect(transformedSnapshot.gate?.modules.first?.ports.contains { $0.name == "bist_logic_bist_signature" } == true)
    }

    @Test("memory BIST requires a complete external engine boundary")
    func memoryBISTRequiresExternalEngineBoundary() async throws {
        let base = DFTBISTConfiguration(
            name: "mbist",
            kind: .memory,
            controllerCellName: "MBIST_CONTROLLER",
            targetInstances: ["u_mem"],
            patternCount: 8,
            signatureRegisterName: "mbist_signature",
            testModeSignal: "test_mode"
        )
        let missingBinding = try await DeterministicBISTEngine().execute(
            makeRequest(operation: .bist, bistConfiguration: base)
        )
        #expect(missingBinding.status == .blocked)
        #expect(missingBinding.dftDiagnostics.contains { $0.code == "DFT_BIST_MEMORY_BINDINGS_MISSING" })

        var configured = base
        configured.memoryBindings = [DFTMemoryBISTBinding(
            instanceName: "u_mem",
            macroType: "SRAM",
            clockPinName: "CLK",
            enablePinName: "CE",
            writeEnablePinName: "WE",
            addressPinNames: ["A0"],
            dataInputPinNames: ["DI0"],
            dataOutputPinNames: ["DO0"],
            algorithmID: "march-c"
        )]
        let qualifiedBoundary = try await DeterministicBISTEngine().execute(
            makeRequest(operation: .bist, bistConfiguration: configured)
        )
        #expect(qualifiedBoundary.status == .blocked)
        #expect(qualifiedBoundary.dftDiagnostics.contains { $0.code == "DFT_BIST_MEMORY_MACRO_UNSUPPORTED" })

        let memoryRequest = makeRequest(operation: .bist, bistConfiguration: configured)
        let externalResponse = DFTResult(
            schemaVersion: DFTRequest.currentSchemaVersion,
            runID: "run-bist",
            status: DFTExecutionStatus.completed,
            provenance: try DFTExecutionSupport.provenance(
                engineID: "external.atpg",
                implementationID: "stub-atpg",
                implementationVersion: "1.0.0",
                inputs: memoryRequest.inputs,
                startedAt: Date(timeIntervalSince1970: 0),
                completedAt: Date(timeIntervalSince1970: 1),
                seed: 1
            ),
            payload: DFTPayload(
                transformedDesign: nil,
                faultCoverage: nil,
                evidenceProvenance: DFTEvidenceProvenance(status: .smokeObserved)
            )
        )
        let backendResult = try await ExternalMemoryBISTEngine(
            runner: StubExternalRunner(response: try DFTArtifactJSONEncoder().encode(externalResponse))
        ).execute(memoryRequest)
        #expect(backendResult.status == .completed)
    }

    @Test("request and payload contracts round-trip through JSON")
    func requestRoundTrip() throws {
        let request = makeRequest(
            operation: .scanInsertion,
            scanArchitecture: scanArchitecture(),
            insertionPolicy: DFTScanInsertionPolicy(scanCellName: "SDFF")
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DFTRequest.self, from: data)

        #expect(decoded == request)
    }

    @Test("documented scan fixture executes through the headless API")
    func documentedScanFixtureExecutes() async throws {
        let requestURL = try #require(
            Bundle.module.url(
                forResource: "scan-request",
                withExtension: "json",
                subdirectory: "Fixtures"
            )
        )
        let fixtureRoot = requestURL.deletingLastPathComponent()
        let request = try JSONDecoder().decode(
            DFTRequest.self,
            from: Data(contentsOf: requestURL)
        )
        let result = try await DefaultDFTEngine(
            artifactStore: InMemoryDFTArtifactStore(),
            designLoader: FileSystemDFTDesignLoader(rootURL: fixtureRoot),
            cellLibraryLoader: FileSystemDFTCellLibraryLoader(rootURL: fixtureRoot)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.artifacts.count == 2)
        #expect(result.payload.designDiff != nil)
    }

    @Test("DFT result directly exposes stable Foundation evidence")
    func resultPreservesFoundationArtifactIdentity() throws {
        let artifact = testArtifact(
            artifactID: "dft-result",
            path: "dft/runs/run-foundation/result.json",
            kind: .report,
            format: .json,
            sha256: String(repeating: "a", count: 64),
            byteCount: 12,
            role: .output
        )
        let timestamp = Date(timeIntervalSince1970: 10)
        let result = DFTResult(
            schemaVersion: DFTRequest.currentSchemaVersion,
            runID: "run-foundation",
            status: .completed,
            diagnostics: [DFTDiagnostic(
                severity: .warning,
                code: "DFT_FIXTURE_WARNING",
                message: "Fixture warning."
            )],
            artifacts: [artifact],
            provenance: try DFTExecutionSupport.provenance(
                engineID: "dft.atpg",
                implementationID: "fixture-atpg",
                implementationVersion: "1",
                startedAt: timestamp,
                completedAt: timestamp.addingTimeInterval(1)
            ),
            payload: DFTPayload(
                transformedDesign: nil,
                faultCoverage: nil
            )
        )
        #expect(result.artifacts.count == 1)
        #expect(result.artifacts[0].id.rawValue == "dft-result")
        #expect(result.artifacts[0].locator.location.value == artifact.path)
        #expect(result.diagnostics[0].code.rawValue == "DFT_FIXTURE_WARNING")
        #expect(result.evidence.provenance == result.provenance)
    }

    @Test("DFT result retains Foundation-derived artifact identity")
    func resultRetainsDerivedArtifactIdentity() throws {
        let timestamp = Date(timeIntervalSince1970: 10)
        let result = DFTResult(
            schemaVersion: DFTRequest.currentSchemaVersion,
            runID: "run-foundation",
            status: .completed,
            artifacts: [testArtifact(
                path: "result.json",
                kind: .report,
                format: .json,
                sha256: String(repeating: "a", count: 64),
                byteCount: 1,
                role: .output
            )],
            provenance: try DFTExecutionSupport.provenance(
                engineID: "dft.atpg",
                implementationID: "fixture-atpg",
                implementationVersion: "1",
                startedAt: timestamp,
                completedAt: timestamp.addingTimeInterval(1)
            ),
            payload: DFTPayload(
                transformedDesign: nil,
                faultCoverage: nil
            )
        )
        #expect(!result.artifacts[0].artifactID.isEmpty)
    }

    @Test("invalid domain diagnostic codes map to a safe Foundation code")
    func invalidDiagnosticCodeFallsBackWithoutTerminating() throws {
        let timestamp = Date(timeIntervalSince1970: 10)
        let result = DFTResult(
            schemaVersion: DFTRequest.currentSchemaVersion,
            runID: "run-foundation",
            status: .blocked,
            diagnostics: [DFTDiagnostic(
                severity: .error,
                code: " invalid diagnostic code",
                message: "Invalid producer code."
            )],
            provenance: try DFTExecutionSupport.provenance(
                engineID: "dft.atpg",
                implementationID: "fixture-atpg",
                implementationVersion: "1",
                startedAt: timestamp,
                completedAt: timestamp.addingTimeInterval(1)
            ),
            payload: DFTPayload(transformedDesign: nil, faultCoverage: nil)
        )

        #expect(result.diagnostics[0].code.rawValue == "dft.invalid-diagnostic-code")
        #expect(result.diagnostics[0].detail == "originalCode:  invalid diagnostic code")
    }

    @Test("STIL and WGL pattern artifacts round-trip")
    func patternFormatsRoundTrip() throws {
        let patternSet = DFTTestPatternSet(
            format: "JSON",
            seed: 7,
            faultUniverseDigest: String(repeating: "a", count: 64),
            patterns: [DFTTestPattern(id: "pattern-1", bits: "0101", faultIDs: ["f1"])]
        )
        let codec = DeterministicTestPatternCodec()

        for format in [DFTTestPatternFormat.stil, .wgl] {
            let data = try codec.encode(patternSet, format: format)
            let decoded = try codec.decode(data, format: format)
            #expect(decoded.seed == patternSet.seed)
            #expect(decoded.faultUniverseDigest == patternSet.faultUniverseDigest)
            #expect(decoded.patterns.map(\.bits) == patternSet.patterns.map(\.bits))
            #expect(decoded.patterns.map(\.faultIDs) == patternSet.patterns.map(\.faultIDs))
        }
    }

    @Test("standard pattern codec rejects malformed metadata")
    func patternCodecRejectsMalformedMetadata() throws {
        let codec = DeterministicTestPatternCodec()
        let malformed = Data("STIL 1.0;\nPatternBurst \"DFTEngine\" {\n  PatList {\n    p1 { 0101; }\n  }\n}\n".utf8)
        var didThrow = false
        do {
            _ = try codec.decode(malformed, format: .stil)
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }

    @Test("external process runner passes a request artifact with timeout control")
    func externalProcessRunner() async throws {
        let runner = ProcessDFTExternalToolRunner(
            descriptor: DFTExternalToolDescriptor(
                engineID: "external.atpg",
                implementationID: "fixture-process",
                implementationVersion: "1"
            ),
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "cat \"$1\"", "fixture", "{request}"],
            timeoutSeconds: 5
        )
        let response = try await runner.run(requestData: Data("{\"request\":true}".utf8))
        #expect(String(decoding: response, as: UTF8.self) == "{\"request\":true}")
    }

    @Test("external ATPG engine preserves the shared result")
    func externalEngine() async throws {
        let request = makeRequest(
            operation: .atpg,
            scanArchitecture: scanArchitecture(),
            faultUniverse: DFTFaultUniverse(
                name: "external",
                revision: "r1",
                faults: [DFTFault(id: "f1", family: .stuckAt, location: "n1")],
                declaredBy: "fixture"
            ),
            atpgConfiguration: DFTATPGConfiguration()
        )
        let expected = try DFTExecutionSupport.result(
            request: request,
            engineID: "external.atpg",
            implementationID: "stub-atpg",
            status: .blocked,
            diagnostics: [],
            payload: DFTPayload(transformedDesign: nil, faultCoverage: nil),
            startedAt: Date()
        )
        let runner = StubExternalRunner(response: try DFTArtifactJSONEncoder().encode(expected))

        let result = try await ExternalATPGEngine(runner: runner).execute(request)

        #expect(result.status == DFTExecutionStatus.blocked)
        #expect(result.runID == request.runID)
        #expect(runner.descriptor.engineID == "external.atpg")

        let store = InMemoryDFTArtifactStore()
        let persisted = try await DFTExternalToolExecutor(
            runner: runner,
            artifactStore: store
        ).execute(request)
        #expect(persisted.evidence.id == expected.evidence.id)
        #expect(persisted.artifacts.map(\.artifactID) == [
            "dft-external-result",
            "dft-external-stdout",
            "dft-external-stderr",
        ])
        #expect(await store.data(for: "dft/runs/run-atpg/external-stderr.raw") == Data())

        do {
            _ = try await DFTExternalToolExecutor(
                runner: StubExternalRunner(
                    response: try DFTArtifactJSONEncoder().encode(expected),
                    standardError: Data("tool failed".utf8),
                    exitCode: 9
                )
            ).execute(request)
            Issue.record("A non-zero external exit must not be decoded as a successful response.")
        } catch let error as DFTExternalToolError {
            #expect(error == .nonZeroExit(
                implementationID: "stub-atpg",
                exitCode: 9,
                standardError: "tool failed"
            ))
        }

        let mismatchedResult = DFTResult(
            schemaVersion: expected.schemaVersion,
            runID: expected.runID,
            status: expected.status,
            provenance: try DFTExecutionSupport.provenance(
                engineID: "external.atpg",
                implementationID: "stub-atpg",
                implementationVersion: "1.0.0",
                inputs: [],
                startedAt: expected.provenance.startedAt,
                completedAt: expected.provenance.completedAt
            ),
            payload: expected.payload
        )
        do {
            _ = try await DFTExternalToolExecutor(
                runner: StubExternalRunner(
                    response: try DFTArtifactJSONEncoder().encode(mismatchedResult)
                )
            ).execute(request)
            Issue.record("External provenance must remain bound to request inputs.")
        } catch let error as DFTExternalToolError {
            #expect(error == .provenanceInputMismatch)
        }
    }

    private func makeRequest(
        operation: DFTOperation,
        testIntent: DFTTestIntent? = nil,
        designDigest: String = String(repeating: "b", count: 64),
        cellLibrary: DFTCellLibraryReference? = nil,
        scanArchitecture: DFTScanArchitecture? = nil,
        insertionPolicy: DFTScanInsertionPolicy? = nil,
        faultUniverse: DFTFaultUniverse? = nil,
        atpgConfiguration: DFTATPGConfiguration? = nil,
        bistConfiguration: DFTBISTConfiguration? = nil
    ) -> DFTRequest {
        let designArtifact = testArtifact(
            artifactID: "design",
            path: "design.json",
            kind: .netlist,
            format: .json,
            sha256: String(repeating: "a", count: 64),
            byteCount: 10,
            role: .input
        )
        let inputArtifacts = [designArtifact] + (cellLibrary.map { [$0.artifact] } ?? [])
        return DFTRequest(
            runID: "run-\(operation.rawValue)",
            inputs: inputArtifacts,
            design: LogicDesignReference(
                artifact: designArtifact,
                topDesignName: "top",
                designDigest: designDigest
            ),
            constraints: DFTConstraintReference(
                artifact: testArtifact(
                    artifactID: "constraints",
                    path: "constraints.sdc",
                    kind: .constraint,
                    format: .sdc,
                    sha256: String(repeating: "c", count: 64),
                    byteCount: 10,
                    role: .input
                ),
                modeIDs: ["functional", "test"]
            ),
            pdk: PDKReference(
                manifest: testArtifact(
                    artifactID: "pdk",
                    path: "pdk.json",
                    kind: .technology,
                    format: .json,
                    sha256: String(repeating: "d", count: 64),
                    byteCount: 10,
                    role: .input
                ),
                processID: "test-process",
                version: "1",
                digest: String(repeating: "e", count: 64)
            ),
            cellLibrary: cellLibrary,
            operation: operation,
            testIntent: testIntent,
            scanArchitecture: scanArchitecture,
            insertionPolicy: insertionPolicy,
            faultUniverse: faultUniverse,
            atpgConfiguration: atpgConfiguration,
            bistConfiguration: bistConfiguration
        )
    }

    private func makeGateSnapshot(sequentialCellCount: Int) -> LogicDesignSnapshot {
        let moduleName = "top"
        let cells = (0..<sequentialCellCount).map { index in
            let instanceName = "u_ff\(index)"
            let qNetID = "q-\(index)"
            let dNetID = "d-\(index)"
            let clockNetID = "clk"
            return GateCell(
                id: "cell-\(index)",
                type: "DFF",
                instanceName: instanceName,
                pins: [
                    GatePin(id: "pin-\(index)-d", name: "D", direction: .input, netID: dNetID),
                    GatePin(id: "pin-\(index)-q", name: "Q", direction: .output, netID: qNetID),
                    GatePin(id: "pin-\(index)-clk", name: "CLK", direction: .input, netID: clockNetID),
                ]
            )
        }
        let nets = (0..<sequentialCellCount).map { index in
            GateNet(id: "d-\(index)", name: "d\(index)")
        } + (0..<sequentialCellCount).map { index in
            GateNet(id: "q-\(index)", name: "q\(index)")
        } + [GateNet(id: "clk", name: "scan_clk")]
        let gate = GateDesign(
            topModuleName: moduleName,
            modules: [
                GateModule(
                    id: "module-top",
                    name: moduleName,
                    ports: [RTLPort(id: "port-clk", name: "clk", direction: .input)],
                    cells: cells,
                    nets: nets
                )
            ]
        )
        return LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: moduleName),
            gate: gate
        )
    }

    private func makeControlledSequentialSnapshot(cellType: String = "DFFRS") -> LogicDesignSnapshot {
        let module = GateModule(
            id: "module-top",
            name: "top",
            ports: [
                RTLPort(id: "port-d", name: "d", direction: .input),
                RTLPort(id: "port-clk", name: "clk", direction: .input),
                RTLPort(id: "port-reset", name: "reset_n", direction: .input),
                RTLPort(id: "port-set", name: "set", direction: .input),
                RTLPort(id: "port-q", name: "q", direction: .output),
            ],
            cells: [GateCell(
                id: "cell-ff",
                type: cellType,
                instanceName: "u_ff",
                pins: [
                    GatePin(id: "pin-d", name: "D", direction: .input, netID: "net-d"),
                    GatePin(id: "pin-q", name: "Q", direction: .output, netID: "net-q"),
                    GatePin(id: "pin-clk", name: "CLK", direction: .input, netID: "net-clk"),
                    GatePin(id: "pin-reset", name: "RESET_N", direction: .input, netID: "net-reset"),
                    GatePin(id: "pin-set", name: "SET", direction: .input, netID: "net-set"),
                ]
            )],
            nets: [
                GateNet(id: "net-d", name: "d"),
                GateNet(id: "net-q", name: "q"),
                GateNet(id: "net-clk", name: "clk"),
                GateNet(id: "net-reset", name: "reset_n"),
                GateNet(id: "net-set", name: "set"),
            ]
        )
        return LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top"),
            gate: GateDesign(topModuleName: "top", modules: [module])
        )
    }

    private func makeLatchSnapshot() -> LogicDesignSnapshot {
        let module = GateModule(
            id: "module-top",
            name: "top",
            ports: [
                RTLPort(id: "port-d", name: "d", direction: .input),
                RTLPort(id: "port-en", name: "en", direction: .input),
                RTLPort(id: "port-q", name: "q", direction: .output),
            ],
            cells: [GateCell(
                id: "cell-latch",
                type: "LATCH",
                instanceName: "u_latch",
                pins: [
                    GatePin(id: "pin-d", name: "D", direction: .input, netID: "net-d"),
                    GatePin(id: "pin-en", name: "EN", direction: .input, netID: "net-en"),
                    GatePin(id: "pin-q", name: "Q", direction: .output, netID: "net-q"),
                ]
            )],
            nets: [
                GateNet(id: "net-d", name: "d"),
                GateNet(id: "net-en", name: "en"),
                GateNet(id: "net-q", name: "q"),
            ]
        )
        return LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top"),
            gate: GateDesign(topModuleName: "top", modules: [module])
        )
    }

    private func makeCombinationalSnapshot() -> LogicDesignSnapshot {
        let andPins = [
            GatePin(id: "and-a", name: "A", direction: .input, netID: "net-a"),
            GatePin(id: "and-b", name: "B", direction: .input, netID: "net-b"),
            GatePin(id: "and-y", name: "Y", direction: .output, netID: "net-n1"),
        ]
        let bufferPins = [
            GatePin(id: "buf-a", name: "A", direction: .input, netID: "net-n1"),
            GatePin(id: "buf-y", name: "Y", direction: .output, netID: "net-y"),
        ]
        let module = GateModule(
            id: "module-top",
            name: "top",
            ports: [
                RTLPort(id: "port-a", name: "a", direction: .input),
                RTLPort(id: "port-b", name: "b", direction: .input),
                RTLPort(id: "port-y", name: "y", direction: .output),
            ],
            cells: [
                GateCell(id: "cell-and", type: "AND2", instanceName: "u_and", pins: andPins),
                GateCell(id: "cell-buffer", type: "BUF", instanceName: "u_buf", pins: bufferPins),
            ],
            nets: [
                GateNet(id: "net-a", name: "a", loadPinIDs: ["and-a"]),
                GateNet(id: "net-b", name: "b", loadPinIDs: ["and-b"]),
                GateNet(id: "net-n1", name: "n1", driverPinIDs: ["and-y"], loadPinIDs: ["buf-a"]),
                GateNet(id: "net-y", name: "y", driverPinIDs: ["buf-y"]),
            ]
        )
        return LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top"),
            gate: GateDesign(topModuleName: "top", modules: [module])
        )
    }

    private func makeSequentialAtpgSnapshot() -> LogicDesignSnapshot {
        let module = GateModule(
            id: "module-top",
            name: "top",
            ports: [
                RTLPort(id: "port-d", name: "d", direction: .input),
                RTLPort(id: "port-clk", name: "clk", direction: .input),
                RTLPort(id: "port-q", name: "q", direction: .output),
            ],
            cells: [GateCell(
                id: "cell-dff",
                type: "DFF",
                instanceName: "u_dff",
                pins: [
                    GatePin(id: "dff-d", name: "D", direction: .input, netID: "net-d"),
                    GatePin(id: "dff-clk", name: "CLK", direction: .input, netID: "net-clk"),
                    GatePin(id: "dff-q", name: "Q", direction: .output, netID: "net-q"),
                ]
            )],
            nets: [
                GateNet(id: "net-d", name: "d", loadPinIDs: ["dff-d"]),
                GateNet(id: "net-clk", name: "clk", loadPinIDs: ["dff-clk"]),
                GateNet(id: "net-q", name: "q", driverPinIDs: ["dff-q"]),
            ]
        )
        return LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top"),
            gate: GateDesign(topModuleName: "top", modules: [module])
        )
    }

    private func scanArchitecture() -> DFTScanArchitecture {
        DFTScanArchitecture(
            name: "core-scan",
            clocks: [DFTScanClock(id: "clk", signalName: "scan_clk", periodNanoseconds: 10)],
            domains: [DFTScanDomain(id: "core", clockID: "clk", chainCount: 1, estimatedElementCount: 4)],
            scanEnableSignal: "scan_en",
            testModeSignal: "test_mode"
        )
    }

    private func makeCellLibraryManifest() -> DFTCellLibraryManifest {
        DFTCellLibraryManifest(
            processID: "test-process",
            version: "1",
            pdkDigest: String(repeating: "e", count: 64),
            bindings: [
                DFTCellLibraryBinding(
                    bindingID: "dff-to-sdff",
                    functionalCellType: "DFF",
                    scanCellType: "SDFF",
                    dataPinName: "D",
                    outputPinName: "Q",
                    clockPinNames: ["CLK"],
                    scanInPinName: "SI",
                    scanEnablePinName: "SE",
                    testModePinName: "TM"
                )
            ],
            evidenceProvenance: DFTEvidenceProvenance(
                status: .corpusObserved,
                corpusRevision: "fixture-m2",
                notes: ["fixture binding only; no foundry trust decision"]
            )
        )
    }

    private func makeCellLibraryReference(
        manifest: DFTCellLibraryManifest
    ) throws -> DFTCellLibraryReference {
        DFTCellLibraryReference(
            artifact: testArtifact(
                artifactID: "cell-library",
                path: "cell-library.json",
                kind: .technology,
                format: .json,
                sha256: String(repeating: "f", count: 64),
                byteCount: 1,
                role: .input
            ),
            processID: manifest.processID,
            version: manifest.version,
            manifestDigest: try DFTCellLibraryManifestCodec.digest(manifest)
        )
    }
}

private struct StubExternalRunner: DFTExternalToolOutputProviding {
    let response: Data
    var standardError = Data()
    var exitCode: Int32 = 0

    var descriptor: DFTExternalToolDescriptor {
        DFTExternalToolDescriptor(
            engineID: "external.atpg",
            implementationID: "stub-atpg",
            implementationVersion: "1.0.0"
        )
    }

    func run(requestData: Data) async throws -> Data {
        response
    }

    func runWithOutput(requestData: Data) async throws -> DFTExternalToolOutput {
        DFTExternalToolOutput(
            standardOutput: response,
            standardError: standardError,
            exitCode: exitCode
        )
    }
}
