import ATPGEngine
import BISTEngine
import CircuiteFoundation
import DFTCore
import DFTEngine
import DFTExternalTools
import DFTPatternExchange
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
            cellLibraryLoader: InMemoryDFTCellLibraryLoader(manifest: libraryManifest),
            timingLibraryLoader: InMemoryDFTTimingLibraryLoader(
                library: try makeTimingLibrary(for: libraryManifest)
            ),
            constraintLoader: FixtureConstraintLoader()
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.scanPlan?.chains.map(\.estimatedElementCount) == [3, 2])
        let implementation = try #require(result.payload.scanImplementation)
        #expect(implementation.chains.map(\.elements.count) == [3, 2])
        #expect(implementation.chains.flatMap(\.elements).map(\.position) == [0, 1, 2, 0, 1])
        #expect(implementation.sourceDesignDigest == sourceDigest)
        #expect(
            implementation.transformedDesignDigest
                == result.payload.transformedDesign?.designDigest
        )
        #expect(result.artifacts.contains { $0 == result.payload.transformedDesign?.artifact })
        #expect(result.payload.transformedDesign?.provenance?.sourceDesignDigest == sourceDigest)
        #expect(result.payload.transformedDesign?.provenance?.transformationID == "dft-scan-insertion")
        #expect(result.payload.designDiff?.changes.count == 5)
        #expect(result.artifacts.count == 3)
        let implementationReference = try #require(
            result.artifacts.first {
                $0.artifactID == "dft-scan-implementation"
            }
        )
        let implementationData = try #require(
            await store.data(for: implementationReference.path)
        )
        #expect(
            try JSONDecoder().decode(
                DFTScanImplementation.self,
                from: implementationData
            ) == implementation
        )
        let diffReference = try #require(
            result.artifacts.first { $0.artifactID == "dft-design-diff" }
        )
        #expect(await store.data(for: diffReference.path) != nil)
        let transformedReference = try #require(
            result.payload.transformedDesign?.artifact
        )
        let transformedData = try #require(
            await store.data(for: transformedReference.path)
        )
        let transformedSnapshot = try LogicDesignSnapshotCodec.decode(transformedData)
        let transformedModule = try #require(transformedSnapshot.gate?.modules.first)
        let transformedCells = transformedModule.cells
        #expect(transformedCells.filter { $0.type == "SDFF" }.count == 5)
        #expect(transformedCells.allSatisfy { $0.type != "DFT_SCAN_OUT" })
        let scanOutputPorts = transformedModule.ports.filter { $0.name.hasPrefix("scan_out_") }
        #expect(scanOutputPorts.count == 2)
        #expect(scanOutputPorts.allSatisfy { port in
            transformedModule.portBindings.contains { $0.portID == port.id }
        })
    }

    @Test("realized scan ATPG emits replayable load capture and unload evidence")
    func realizedScanATPG() async throws {
        let store = InMemoryDFTArtifactStore()
        var sourceSnapshot = makeGateSnapshot(sequentialCellCount: 2)
        for index in 0..<2 {
            sourceSnapshot.gate?.modules[0].ports.append(
                RTLPort(
                    id: "port-d-\(index)",
                    name: "d\(index)",
                    direction: .input
                )
            )
            sourceSnapshot.gate?.modules[0].portBindings.append(
                GatePortBinding(
                    portID: "port-d-\(index)",
                    netID: "d-\(index)"
                )
            )
        }
        let sourceDigest = try LogicDesignSnapshotCodec.digest(sourceSnapshot)
        let libraryManifest = makeCellLibraryManifest()
        let libraryReference = try makeCellLibraryReference(
            manifest: libraryManifest
        )
        let architecture = DFTScanArchitecture(
            name: "core-scan",
            clocks: [
                DFTScanClock(
                    id: "clk",
                    signalName: "scan_clk",
                    periodNanoseconds: 10
                )
            ],
            domains: [
                DFTScanDomain(
                    id: "core",
                    clockID: "clk",
                    chainCount: 2,
                    estimatedElementCount: 2
                )
            ],
            scanEnableSignal: "scan_en",
            testModeSignal: "test_mode"
        )
        let scanRequest = makeRequest(
            operation: .scanInsertion,
            designDigest: sourceDigest,
            cellLibrary: libraryReference,
            scanArchitecture: architecture,
            insertionPolicy: DFTScanInsertionPolicy(scanCellName: "SDFF")
        )
        let scanResult = try await DeterministicScanInsertionEngine(
            artifactStore: store,
            designLoader: InMemoryDFTDesignLoader(snapshot: sourceSnapshot),
            cellLibraryLoader: InMemoryDFTCellLibraryLoader(
                manifest: libraryManifest
            ),
            timingLibraryLoader: InMemoryDFTTimingLibraryLoader(
                library: try makeTimingLibrary(for: libraryManifest)
            ),
            constraintLoader: FixtureConstraintLoader()
        ).execute(scanRequest)
        let transformedReference = try #require(
            scanResult.payload.transformedDesign
        )
        let implementation = try #require(
            scanResult.payload.scanImplementation
        )
        let implementationArtifact = try #require(
            scanResult.artifacts.first {
                $0.artifactID == "dft-scan-implementation"
            }
        )
        let transformedData = try await store.data(
            for: transformedReference.artifact
        )
        let transformedSnapshot = try LogicDesignSnapshotCodec.decode(
            transformedData
        )

        var atpgRequest = makeRequest(
            operation: .atpg,
            designDigest: transformedReference.designDigest,
            scanArchitecture: architecture,
            atpgConfiguration: DFTATPGConfiguration(
                patternLength: 16,
                faultSource: .gateLevel,
                maximumExhaustiveInputCount: 8
            )
        )
        atpgRequest.design = transformedReference
        atpgRequest.inputs = [
            transformedReference.artifact,
            implementationArtifact,
        ]
        atpgRequest.scanImplementation = DFTScanImplementationReference(
            artifact: implementationArtifact,
            transformedDesignDigest: transformedReference.designDigest
        )

        let result = try await DeterministicATPGEngine(
            artifactStore: store,
            designLoader: InMemoryDFTDesignLoader(
                snapshot: transformedSnapshot
            ),
            constraintLoader: FixtureConstraintLoader()
        ).execute(atpgRequest)

        #expect(result.status == .completed)
        #expect(result.payload.faultCoverage == 1)
        let plan = try #require(result.payload.scanPatternExecutionPlan)
        #expect(plan.transformedDesignDigest == transformedReference.designDigest)
        #expect(plan.patterns.count == result.payload.patterns?.patterns.count)
        #expect(plan.patterns.allSatisfy {
            $0.chains.count == implementation.chains.count
                && $0.chains.allSatisfy {
                    $0.loadBits.count == $0.elementOutputNetIDs.count
                        && $0.expectedUnloadBits.count
                            == $0.elementOutputNetIDs.count
                }
        })
        #expect(result.artifacts.contains {
            $0.artifactID == "dft-scan-pattern-execution-plan"
        })
        let faultUniverseArtifact = try #require(
            result.artifacts.first {
                $0.artifactID == "dft-fault-universe"
            }
        )
        let retainedFaultUniverse = try JSONDecoder().decode(
            DFTFaultUniverse.self,
            from: try await store.data(for: faultUniverseArtifact)
        )
        #expect(
            retainedFaultUniverse.faults.map(\.id)
                == result.payload.coverageEvidence?.outcomes.map(\.faultID)
        )
        var missingFaultUniverseResult = result
        missingFaultUniverseResult.artifacts.removeAll {
            $0.artifactID == "dft-fault-universe"
        }
        #expect(throws: DFTResultValidationError.self) {
            try DFTResultValidator().validate(
                missingFaultUniverseResult,
                for: atpgRequest
            )
        }
        let exchangeProgram = try DFTScanPatternExchangeConverter().program(
            from: plan,
            name: "realized_scan"
        )
        let stilData = try STILPatternCodec().encode(exchangeProgram)
        #expect(try STILPatternCodec().decode(stilData) == exchangeProgram)
        var missingScanInputPlan = plan
        let scanInputSignal = try #require(
            missingScanInputPlan.patterns.first?.chains.first?.scanInSignal
        )
        missingScanInputPlan.patterns[0].capture.primaryInputs.removeValue(
            forKey: scanInputSignal
        )
        #expect(throws: DFTPatternExchangeError.self) {
            try DFTScanPatternExchangeConverter().program(
                from: missingScanInputPlan,
                name: "missing_scan_input"
            )
        }
        try await GateLevelATPGResultSemanticVerifier().validate(
            result,
            for: atpgRequest,
            design: transformedSnapshot,
            scanImplementation: implementation
        )

        var tampered = result
        let retainedUnload = try #require(
            tampered.payload.scanPatternExecutionPlan?
                .patterns[0].chains[0].expectedUnloadBits
        )
        tampered.payload.scanPatternExecutionPlan?
            .patterns[0].chains[0].expectedUnloadBits =
                retainedUnload == "0" ? "1" : "0"
        await #expect(throws: DFTResultSemanticValidationError.self) {
            try await GateLevelATPGResultSemanticVerifier().validate(
                tampered,
                for: atpgRequest,
                design: transformedSnapshot,
                scanImplementation: implementation
            )
        }

        var duplicateExecutionResult = result
        let duplicateExecution = try #require(
            duplicateExecutionResult.payload.scanPatternExecutionPlan?
                .patterns.first
        )
        duplicateExecutionResult.payload.scanPatternExecutionPlan?
            .patterns.append(duplicateExecution)
        #expect(throws: DFTResultValidationError.self) {
            try DFTResultValidator().validate(
                duplicateExecutionResult,
                for: atpgRequest
            )
        }

        var incompleteExecutionResult = result
        incompleteExecutionResult.payload.scanPatternExecutionPlan?
            .patterns[0].chains.removeAll()
        await #expect(throws: DFTResultSemanticValidationError.self) {
            try await GateLevelATPGResultSemanticVerifier().validate(
                incompleteExecutionResult,
                for: atpgRequest,
                design: transformedSnapshot,
                scanImplementation: implementation
            )
        }
    }

    @Test("scan compression inserts explicit decompressor and compactor connectivity")
    func scanCompressionInsertion() async throws {
        let store = InMemoryDFTArtifactStore()
        let sourceSnapshot = makeGateSnapshot(sequentialCellCount: 4)
        let sourceDigest = try LogicDesignSnapshotCodec.digest(sourceSnapshot)
        let libraryManifest = makeCellLibraryManifest(
            scanCompressionMapping: makeScanCompressionCellMapping(chainCount: 4)
        )
        let libraryReference = try makeCellLibraryReference(manifest: libraryManifest)
        let architecture = DFTScanArchitecture(
            name: "compressed-scan",
            clocks: [DFTScanClock(
                id: "clk",
                signalName: "scan_clk",
                periodNanoseconds: 10
            )],
            domains: [DFTScanDomain(
                id: "core",
                clockID: "clk",
                chainCount: 4,
                estimatedElementCount: 4
            )],
            compression: DFTCompressionConfiguration(
                enabled: true,
                ratio: 4,
                scanInputSignals: ["compressed_scan_in"],
                scanOutputSignals: ["compressed_scan_out"]
            ),
            scanEnableSignal: "scan_en",
            testModeSignal: "test_mode"
        )
        let request = makeRequest(
            operation: .scanInsertion,
            designDigest: sourceDigest,
            cellLibrary: libraryReference,
            scanArchitecture: architecture,
            insertionPolicy: DFTScanInsertionPolicy(scanCellName: "SDFF")
        )

        let result = try await DeterministicScanInsertionEngine(
            artifactStore: store,
            designLoader: InMemoryDFTDesignLoader(snapshot: sourceSnapshot),
            cellLibraryLoader: InMemoryDFTCellLibraryLoader(manifest: libraryManifest),
            timingLibraryLoader: InMemoryDFTTimingLibraryLoader(
                library: try makeTimingLibrary(for: libraryManifest)
            ),
            constraintLoader: FixtureConstraintLoader()
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.designDiff?.changes.count == 6)
        let transformedReference = try #require(result.payload.transformedDesign?.artifact)
        let transformedData = try #require(await store.data(for: transformedReference.path))
        let transformed = try LogicDesignSnapshotCodec.decode(transformedData)
        let module = try #require(transformed.gate?.modules.first)
        let decompressor = try #require(module.cells.first {
            $0.type == "SCAN_DECOMPRESSOR"
        })
        let compactor = try #require(module.cells.first {
            $0.type == "SCAN_COMPACTOR"
        })
        #expect(decompressor.pins.filter { $0.direction == .input }.count == 1)
        #expect(decompressor.pins.filter { $0.direction == .output }.count == 4)
        #expect(compactor.pins.filter { $0.direction == .input }.count == 4)
        #expect(compactor.pins.filter { $0.direction == .output }.count == 1)
        #expect(module.ports.contains {
            $0.name == "compressed_scan_in" && $0.direction == .input
        })
        #expect(module.ports.contains {
            $0.name == "compressed_scan_out" && $0.direction == .output
        })
        #expect(!module.ports.contains { $0.name.hasPrefix("scan_in_core_") })
        #expect(!module.ports.contains { $0.name.hasPrefix("scan_out_core_") })
        for pin in decompressor.pins + compactor.pins {
            let net = try #require(module.nets.first { $0.id == pin.netID })
            switch pin.direction {
            case .input:
                #expect(net.loadPinIDs.contains(pin.id))
            case .output:
                #expect(net.driverPinIDs.contains(pin.id))
            case .inOut:
                Issue.record("Compression helpers must not use bidirectional pins.")
            }
        }
    }

    @Test(
        "compressed scan transformation stays within the large-chain latency budget",
        .timeLimit(.minutes(1))
    )
    func scanCompressionPerformanceBudget() throws {
        let chainCount = 2_048
        let source = makeGateSnapshot(sequentialCellCount: chainCount)
        let architecture = DFTScanArchitecture(
            name: "large-compressed-scan",
            clocks: [DFTScanClock(
                id: "clk",
                signalName: "scan_clk",
                periodNanoseconds: 10
            )],
            domains: [DFTScanDomain(
                id: "core",
                clockID: "clk",
                chainCount: chainCount,
                estimatedElementCount: chainCount
            )],
            compression: DFTCompressionConfiguration(
                enabled: true,
                ratio: Double(chainCount),
                scanInputSignals: ["compressed_scan_in"],
                scanOutputSignals: ["compressed_scan_out"]
            ),
            scanEnableSignal: "scan_en",
            testModeSignal: "test_mode"
        )
        let plan = try DeterministicScanPlanner().plan(architecture)
        let clock = ContinuousClock()
        let startedAt = clock.now

        let result = try DFTGateLevelScanTransformer().transform(
            snapshot: source,
            architecture: architecture,
            plan: plan,
            policy: DFTScanInsertionPolicy(scanCellName: "SDFF"),
            cellLibrary: makeCellLibraryManifest(
                scanCompressionMapping: makeScanCompressionCellMapping(chainCount: chainCount)
            )
        )

        let elapsed = startedAt.duration(to: clock.now)
        #expect(result.transformedCellIDs.count == chainCount)
        #expect(result.helperCellIDs.count == 2)
        #expect(elapsed < .seconds(5))
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
            cellLibraryLoader: InMemoryDFTCellLibraryLoader(manifest: libraryManifest),
            timingLibraryLoader: InMemoryDFTTimingLibraryLoader(
                library: try makeTimingLibrary(for: libraryManifest)
            ),
            constraintLoader: FixtureConstraintLoader()
        ).execute(request)

        #expect(result.status == .blocked)
        #expect(result.dftDiagnostics.contains { $0.code == "DFT_DESIGN_LOADER_MISSING" })
    }

    @Test("scan insertion blocks when constraint loading is unavailable")
    func scanInsertionRequiresConstraintLoader() async throws {
        let sourceSnapshot = makeGateSnapshot(sequentialCellCount: 1)
        let sourceDigest = try LogicDesignSnapshotCodec.digest(sourceSnapshot)
        let libraryManifest = makeCellLibraryManifest()
        let request = makeRequest(
            operation: .scanInsertion,
            designDigest: sourceDigest,
            cellLibrary: try makeCellLibraryReference(manifest: libraryManifest),
            scanArchitecture: scanArchitecture(),
            insertionPolicy: DFTScanInsertionPolicy(scanCellName: "SDFF")
        )

        let result = try await DeterministicScanInsertionEngine(
            designLoader: InMemoryDFTDesignLoader(snapshot: sourceSnapshot),
            cellLibraryLoader: InMemoryDFTCellLibraryLoader(manifest: libraryManifest),
            timingLibraryLoader: InMemoryDFTTimingLibraryLoader(
                library: try makeTimingLibrary(for: libraryManifest)
            )
        ).execute(request)

        #expect(result.status == .blocked)
        #expect(result.dftDiagnostics.contains {
            $0.code == "DFT_CONSTRAINT_VALIDATION_FAILED"
                && $0.message.contains("unavailable")
        })
    }

    @Test("scan insertion requires every declared constraint mode")
    func scanInsertionRequiresExactConstraintModes() async throws {
        let sourceSnapshot = makeGateSnapshot(sequentialCellCount: 1)
        let sourceDigest = try LogicDesignSnapshotCodec.digest(sourceSnapshot)
        let libraryManifest = makeCellLibraryManifest()
        let request = makeRequest(
            operation: .scanInsertion,
            designDigest: sourceDigest,
            cellLibrary: try makeCellLibraryReference(manifest: libraryManifest),
            scanArchitecture: scanArchitecture(),
            insertionPolicy: DFTScanInsertionPolicy(scanCellName: "SDFF")
        )

        let result = try await DeterministicScanInsertionEngine(
            designLoader: InMemoryDFTDesignLoader(snapshot: sourceSnapshot),
            cellLibraryLoader: InMemoryDFTCellLibraryLoader(manifest: libraryManifest),
            timingLibraryLoader: InMemoryDFTTimingLibraryLoader(
                library: try makeTimingLibrary(for: libraryManifest)
            ),
            constraintLoader: MissingModeConstraintLoader()
        ).execute(request)

        #expect(result.status == .blocked)
        #expect(result.dftDiagnostics.contains {
            $0.code == "DFT_CONSTRAINT_VALIDATION_FAILED"
        })
    }

    @Test("request validation rejects a PDK digest detached from its manifest")
    func requestRequiresExactPDKIdentity() {
        var request = makeRequest(
            operation: .scanInsertion,
            scanArchitecture: scanArchitecture(),
            insertionPolicy: DFTScanInsertionPolicy(scanCellName: "SDFF")
        )
        request.pdk.digest = String(repeating: "f", count: 64)

        #expect(request.validationIssues(for: .scanInsertion).contains {
            $0.code == "DFT_PDK_IDENTITY_MISMATCH"
        })
    }

    @Test("request validation rejects non-finite scan timing")
    func requestRejectsNonFiniteScanTiming() {
        var architecture = scanArchitecture()
        architecture.clocks[0].periodNanoseconds = .nan
        let request = makeRequest(
            operation: .scanInsertion,
            scanArchitecture: architecture,
            insertionPolicy: DFTScanInsertionPolicy(scanCellName: "SDFF")
        )

        #expect(request.validationIssues(for: .scanInsertion).contains {
            $0.code == "DFT_SCAN_CLOCK_PARAMETERS_INVALID"
        })
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
            cellLibraryLoader: InMemoryDFTCellLibraryLoader(manifest: libraryManifest),
            timingLibraryLoader: InMemoryDFTTimingLibraryLoader(
                library: try makeTimingLibrary(for: libraryManifest)
            ),
            constraintLoader: FixtureConstraintLoader(
                clockSignal: "unbound_clock"
            )
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
            cellLibraryLoader: InMemoryDFTCellLibraryLoader(manifest: mismatchedManifest),
            timingLibraryLoader: InMemoryDFTTimingLibraryLoader(
                library: try makeTimingLibrary(for: mismatchedManifest)
            ),
            constraintLoader: FixtureConstraintLoader()
        ).execute(request)

        #expect(result.status == .blocked)
        #expect(result.dftDiagnostics.contains { $0.code == "DFT_CELL_LIBRARY_LOAD_FAILED" })
        #expect(result.dftDiagnostics.contains { $0.message.contains("pdkDigest") })
    }

    @Test("cell-library validation rejects ambiguous scan-compression pin mappings")
    func scanCompressionMappingMustBeUnambiguous() {
        var manifest = makeCellLibraryManifest(
            scanCompressionMapping: makeScanCompressionCellMapping(chainCount: 2)
        )
        manifest.scanCompressionMapping?.decompressorOutputPinNames = ["O", "O"]

        #expect(throws: DFTCellLibraryError.self) {
            try DFTCellLibraryManifestCodec.validate(manifest)
        }
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
        let engine = DeterministicATPGEngine(
            artifactStore: store,
            constraintLoader: FixtureConstraintLoader()
        )

        let first = try await engine.execute(request)
        let second = try await engine.execute(request)

        #expect(first.status == .blocked)
        #expect(first.payload.faultCoverage == nil)
        #expect(first.payload.coverageEvidence?.detectedFaultCount == 0)
        #expect(first.payload.coverageEvidence?.abortedFaultCount == 2)
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
            designLoader: InMemoryDFTDesignLoader(snapshot: snapshot),
            constraintLoader: FixtureConstraintLoader()
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.faultCoverage == 1)
        #expect(result.payload.coverageEvidence?.declaredFaultCount == 4)
        #expect(result.payload.coverageEvidence?.detectedFaultCount == 4)
        #expect(result.payload.patterns?.patterns.count == 4)
        #expect(result.payload.patterns?.patterns.allSatisfy { $0.bits.count == 2 } == true)
        #expect(result.dftDiagnostics.contains { $0.code == "DFT_GATE_LEVEL_ATPG_COMPLETED" })
        try await GateLevelATPGResultSemanticVerifier().validate(
            result,
            for: request,
            design: snapshot
        )
        await #expect(throws: DFTResultSemanticValidationError.self) {
            try await GateLevelATPGResultSemanticVerifier(
                combinationalSimulator: NonDetectingGateLevelSimulator()
            ).validate(
                result,
                for: request,
                design: snapshot
            )
        }
    }

    @Test("completed ATPG rejects aggregate coverage without exact fault outcomes")
    func completedATPGRequiresExactFaultOutcomes() async throws {
        let snapshot = makeCombinationalSnapshot()
        let request = makeRequest(
            operation: .atpg,
            designDigest: try LogicDesignSnapshotCodec.digest(snapshot),
            scanArchitecture: scanArchitecture(),
            atpgConfiguration: DFTATPGConfiguration(
                patternLength: 2,
                faultSource: .gateLevel
            )
        )
        var result = try await DeterministicATPGEngine(
            designLoader: InMemoryDFTDesignLoader(snapshot: snapshot),
            constraintLoader: FixtureConstraintLoader()
        ).execute(request)
        result.payload.coverageEvidence?.outcomes.removeLast()

        do {
            try DFTResultValidator().validate(result, for: request)
            Issue.record("Aggregate coverage must not replace exact per-fault evidence.")
        } catch let error as DFTResultValidationError {
            guard case .coverageInvalid = error else {
                Issue.record("Unexpected validation error: \(error.localizedDescription)")
                return
            }
        }
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
            designLoader: InMemoryDFTDesignLoader(snapshot: snapshot),
            constraintLoader: FixtureConstraintLoader()
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
                    portBindings: [
                        GatePortBinding(portID: "port-scan-in", netID: "net-scan-in"),
                        GatePortBinding(portID: "port-scan-en", netID: "net-scan-en"),
                        GatePortBinding(portID: "port-clk", netID: "net-clk"),
                        GatePortBinding(portID: "port-d", netID: "net-d"),
                        GatePortBinding(portID: "port-q", netID: "net-q"),
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
            designLoader: InMemoryDFTDesignLoader(snapshot: snapshot),
            constraintLoader: FixtureConstraintLoader()
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
            designLoader: InMemoryDFTDesignLoader(snapshot: snapshot),
            constraintLoader: FixtureConstraintLoader()
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
                scanEnablePinName: "SE",
                legalReplacementGroup: "scan-flops"
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
            cellLibraryLoader: InMemoryDFTCellLibraryLoader(manifest: manifest),
            timingLibraryLoader: InMemoryDFTTimingLibraryLoader(
                library: try makeTimingLibrary(for: manifest)
            ),
            constraintLoader: FixtureConstraintLoader()
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
            designLoader: InMemoryDFTDesignLoader(snapshot: snapshot),
            constraintLoader: FixtureConstraintLoader()
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

        let result = try await DeterministicATPGEngine(
            constraintLoader: FixtureConstraintLoader()
        ).execute(request)

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

        let result = try await DeterministicATPGEngine(
            constraintLoader: FixtureConstraintLoader()
        ).execute(request)

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

        let result = try await DeterministicATPGEngine(
            constraintLoader: FixtureConstraintLoader()
        ).execute(request)

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
            constraintLoader: FixtureConstraintLoader(),
            processFaultModel: ProcessSpecificFaultModelFixture(),
            processFaultPatternVerifier: ProcessSpecificFaultPatternVerifierFixture()
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.faultCoverage == 1)
        #expect(result.payload.patterns?.patterns.first?.bits == "11111111")
        #expect(result.payload.coverageEvidence?.outcomes.first?.modelID == "fixture-process-fault-model")
        #expect(
            result.payload.coverageEvidence?.outcomes.first?.verificationID
                == "fixture-independent-process-pattern-verifier"
        )
        #expect(
            result.payload.coverageEvidence?.outcomes.first?
                .processCaptureTiming?.clockSignal == "scan_clk"
        )
        #expect(result.payload.evidenceProvenance.status == .smokeObserved)
        #expect(result.dftDiagnostics.contains { $0.code == "DFT_ATPG_COMPLETED" })
    }

    @Test("process-specific ATPG rejects model self-approval")
    func processSpecificFaultModelRequiresIndependentPatternVerifier() async throws {
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
            constraintLoader: FixtureConstraintLoader(),
            processFaultModel: ProcessSpecificFaultModelFixture()
        ).execute(request)

        #expect(result.status == .blocked)
        #expect(result.payload.faultCoverage == nil)
        #expect(result.dftDiagnostics.contains {
            $0.code == "DFT_PROCESS_FAULT_PATTERN_VERIFIER_MISSING"
        })
    }

    @Test("process-specific ATPG rejects unbound capture timing")
    func processSpecificFaultModelRequiresBoundCaptureTiming() async throws {
        let request = makeProcessSpecificATPGRequest()
        let invalidTiming = DFTProcessCaptureTiming(
            clockSignal: "undeclared_clock",
            launchEdge: .rising,
            captureEdge: .rising,
            launchToCaptureNanoseconds: 10,
            sampleOffsetNanoseconds: 9,
            assumptions: ["fixture timing references an undeclared clock"]
        )

        let result = try await DeterministicATPGEngine(
            constraintLoader: FixtureConstraintLoader(),
            processFaultModel: ProcessSpecificFaultModelFixture(
                captureTiming: invalidTiming
            ),
            processFaultPatternVerifier: ProcessSpecificFaultPatternVerifierFixture()
        ).execute(request)

        #expect(result.status == .blocked)
        #expect(result.payload.faultCoverage == nil)
        #expect(result.dftDiagnostics.contains {
            $0.code == "DFT_PROCESS_FAULT_CAPTURE_TIMING_INVALID"
        })
    }

    @Test("process-specific ATPG retains independent pattern rejection")
    func processSpecificFaultPatternRejectionBlocksCoverage() async throws {
        let result = try await DeterministicATPGEngine(
            constraintLoader: FixtureConstraintLoader(),
            processFaultModel: ProcessSpecificFaultModelFixture(),
            processFaultPatternVerifier: ProcessSpecificFaultPatternVerifierFixture(
                acceptedPattern: "00000000"
            )
        ).execute(makeProcessSpecificATPGRequest())

        #expect(result.status == .blocked)
        #expect(result.payload.faultCoverage == nil)
        #expect(
            result.payload.coverageEvidence?.outcomes.first?.verificationID
                == "fixture-independent-process-pattern-verifier"
        )
        #expect(result.dftDiagnostics.contains {
            $0.code == "DFT_PROCESS_FAULT_PATTERN_REJECTED"
        })
    }

    @Test("ATPG capability report does not advertise blocked standard formats")
    func atpgCapabilityReportMatchesExecutableFormatContract() {
        let unavailable = DeterministicATPGEngine().capabilityReport
        #expect(unavailable.capabilities["stil_export"] == .blocked)
        #expect(unavailable.capabilities["wgl_export"] == .blocked)
        #expect(unavailable.capabilities["process_specific_faults"] == .blocked)

        let processBound = DeterministicATPGEngine(
            processFaultModel: ProcessSpecificFaultModelFixture(),
            processFaultPatternVerifier: ProcessSpecificFaultPatternVerifierFixture()
        ).capabilityReport
        #expect(processBound.capabilities["process_specific_faults"] == .available)
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

        let result = try await DeterministicATPGEngine(
            constraintLoader: FixtureConstraintLoader()
        ).execute(request)

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
                targetInstances: ["u_ff0"],
                patternCount: 128,
                signatureRegisterName: "misr_q",
                clockSignal: "scan_clk",
                targetBindings: [DFTBISTTargetBinding(
                    instanceName: "u_ff0",
                    patternInputPinNames: ["D"],
                    responseOutputPinNames: ["Q"]
                )],
                logicCellMapping: makeLogicBISTCellMapping()
            )
        )

        let result = try await DeterministicBISTEngine(
            artifactStore: store,
            designLoader: InMemoryDFTDesignLoader(snapshot: sourceSnapshot),
            constraintLoader: FixtureConstraintLoader(),
            logicBISTCellMappingLoader: FixtureLogicBISTCellMappingLoader()
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.bistStructure?.name == "logic-bist")
        #expect(result.payload.designDiff?.changes.count ?? 0 > 1)
        #expect(result.artifacts.count == 3)
        #expect(result.payload.transformedDesign?.provenance?.sourceDesignDigest == sourceDigest)
        #expect(result.payload.transformedDesign?.provenance?.transformationID == "dft-bist-insertion")
        let transformedReference = try #require(
            result.payload.transformedDesign?.artifact
        )
        let transformedData = try #require(
            await store.data(for: transformedReference.path)
        )
        let transformedSnapshot = try LogicDesignSnapshotCodec.decode(transformedData)
        let transformedCells = try #require(transformedSnapshot.gate?.modules.first?.cells)
        #expect(transformedCells.contains { $0.type == "LBIST_INPUT_MUX" })
        #expect(transformedCells.contains { $0.type == "LBIST_RESPONSE_COMPACTOR" })
        #expect(transformedSnapshot.gate?.modules.first?.ports.contains { $0.name == "bist_logic_bist_signature" } == true)
        #expect(result.payload.bistStructure?.logicCellMapping == makeLogicBISTCellMapping())
    }

    @Test("logic BIST blocks a mapping artifact that differs from its inline contract")
    func logicBISTRequiresExactMappingArtifact() async throws {
        let sourceSnapshot = makeGateSnapshot(sequentialCellCount: 1)
        let sourceDigest = try LogicDesignSnapshotCodec.digest(sourceSnapshot)
        let mapping = makeLogicBISTCellMapping()
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
                targetInstances: ["u_ff0"],
                patternCount: 128,
                signatureRegisterName: "misr_q",
                clockSignal: "scan_clk",
                targetBindings: [DFTBISTTargetBinding(
                    instanceName: "u_ff0",
                    patternInputPinNames: ["D"],
                    responseOutputPinNames: ["Q"]
                )],
                logicCellMapping: mapping
            )
        )
        var mismatchedManifest = mapping.manifest
        mismatchedManifest.expectedSignature = "0000"

        let result = try await DeterministicBISTEngine(
            designLoader: InMemoryDFTDesignLoader(snapshot: sourceSnapshot),
            constraintLoader: FixtureConstraintLoader(),
            logicBISTCellMappingLoader: FixedLogicBISTCellMappingLoader(
                manifest: mismatchedManifest
            )
        ).execute(request)

        #expect(result.status == .blocked)
        #expect(result.dftDiagnostics.contains {
            $0.code == "DFT_BIST_CELL_MAPPING_LOAD_FAILED"
        })
    }

    @Test("memory BIST transforms explicitly bound macros and retains its structure")
    func memoryBISTTransformsBoundMacros() async throws {
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
        let mappingMissing = try await DeterministicBISTEngine(
            constraintLoader: FixtureConstraintLoader()
        ).execute(
            makeRequest(operation: .bist, bistConfiguration: configured)
        )
        #expect(mappingMissing.status == .blocked)
        #expect(mappingMissing.dftDiagnostics.contains {
            $0.code == "DFT_BIST_MEMORY_CELL_MAPPING_MISSING"
        })

        let mapping = DFTMemoryBISTCellMapping(
            artifact: testArtifact(
                artifactID: "memory-bist-cell-mapping",
                path: "memory-bist-cell-mapping.json",
                kind: .technology,
                format: .json,
                sha256: String(repeating: "7", count: 64),
                byteCount: 1,
                role: .input
            ),
            processID: "test-process",
            pdkDigest: String(repeating: "e", count: 64),
            controllerCellType: "MBIST_CONTROLLER",
            inputMuxCellType: "MBIST_INPUT_MUX",
            responseCompactorCellType: "MBIST_COMPACTOR",
            signatureRegisterCellType: "MBIST_SIGNATURE",
            supportedMacroTypes: ["SRAM"],
            supportedAlgorithmIDs: ["march-c"]
        )
        configured.memoryCellMapping = mapping
        let sourceSnapshot = makeMemorySnapshot()
        let request = makeRequest(
            operation: .bist,
            designDigest: try LogicDesignSnapshotCodec.digest(sourceSnapshot),
            bistConfiguration: configured
        )
        let store = InMemoryDFTArtifactStore()
        let completed = try await DeterministicBISTEngine(
            artifactStore: store,
            designLoader: InMemoryDFTDesignLoader(snapshot: sourceSnapshot),
            constraintLoader: FixtureConstraintLoader(),
            memoryBISTCellMappingLoader: FixtureMemoryBISTCellMappingLoader()
        ).execute(request)

        #expect(completed.status == .completed)
        #expect(completed.payload.bistStructure?.memoryBindings == configured.memoryBindings)
        #expect(completed.payload.bistStructure?.memoryCellMapping == mapping)
        let transformedReference = try #require(completed.payload.transformedDesign?.artifact)
        let transformedData = try #require(await store.data(for: transformedReference.path))
        let transformed = try LogicDesignSnapshotCodec.decode(transformedData)
        let module = try #require(transformed.gate?.modules.first)
        #expect(module.cells.contains { $0.type == "MBIST_CONTROLLER" })
        #expect(module.cells.filter { $0.type == "MBIST_INPUT_MUX" }.count == 4)
        #expect(module.cells.contains { $0.type == "MBIST_COMPACTOR" })
        #expect(module.cells.contains { $0.type == "MBIST_SIGNATURE" })
        let macro = try #require(module.cells.first { $0.instanceName == "u_mem" })
        #expect(macro.pins.first { $0.name == "CE" }?.netID?.contains("mbist_") == true)
        #expect(macro.pins.first { $0.name == "WE" }?.netID?.contains("mbist_") == true)

        let memoryRequest = request
        let externalResponse = DFTResult(
            schemaVersion: DFTRequest.currentSchemaVersion,
            runID: "run-bist",
            status: DFTExecutionStatus.completed,
            provenance: try DFTExecutionSupport.provenance(
                engineID: stubExternalBinaryDigest,
                implementationID: "stub-atpg",
                implementationVersion: "1.0.0",
                inputs: memoryRequest.executionInputArtifacts,
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
        do {
            _ = try await ExternalMemoryBISTEngine(
                runner: StubExternalRunner(
                    response: try DFTArtifactJSONEncoder().encode(externalResponse)
                )
            ).execute(memoryRequest)
            Issue.record("A completed memory-BIST result without transformed evidence must be rejected.")
        } catch let error as DFTResultValidationError {
            #expect(error == .completedPayloadIncomplete(.bist))
        }
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

    @Test("ambiguous compression and standard exporters fail closed")
    func unsupportedCapabilitiesFailClosed() {
        var compressedArchitecture = scanArchitecture()
        compressedArchitecture.compression = DFTCompressionConfiguration(
            enabled: true,
            ratio: 4
        )
        let scanRequest = makeRequest(
            operation: .scanInsertion,
            cellLibrary: nil,
            scanArchitecture: compressedArchitecture,
            insertionPolicy: DFTScanInsertionPolicy(scanCellName: "SDFF")
        )
        #expect(scanRequest.validationIssues(for: .scanInsertion).contains {
            $0.code == "DFT_COMPRESSION_CHANNELS_INVALID"
        })

        compressedArchitecture.compression = DFTCompressionConfiguration(
            enabled: true,
            ratio: 4,
            scanInputSignals: ["scan_en"],
            scanOutputSignals: ["compressed_scan_out"]
        )
        let conflictingChannelRequest = makeRequest(
            operation: .scanInsertion,
            cellLibrary: nil,
            scanArchitecture: compressedArchitecture,
            insertionPolicy: DFTScanInsertionPolicy(scanCellName: "SDFF")
        )
        #expect(conflictingChannelRequest.validationIssues(for: .scanInsertion).contains {
            $0.code == "DFT_COMPRESSION_CHANNEL_CONFLICT"
        })

        let atpgRequest = makeRequest(
            operation: .atpg,
            scanArchitecture: scanArchitecture(),
            faultUniverse: DFTFaultUniverse(
                name: "fixture",
                revision: "1",
                faults: [DFTFault(id: "f1", family: .stuckAt, location: "n1")],
                declaredBy: "fixture"
            ),
            atpgConfiguration: DFTATPGConfiguration(patternFormat: .stil)
        )
        #expect(atpgRequest.validationIssues(for: .atpg).contains {
            $0.code == "DFT_STANDARD_PATTERN_EXPORT_UNQUALIFIED"
        })
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
        let store = InMemoryDFTArtifactStore()
        let result = try await DefaultDFTEngine(
            artifactStore: store,
            designLoader: FileSystemDFTDesignLoader(rootURL: fixtureRoot),
            cellLibraryLoader: FileSystemDFTCellLibraryLoader(rootURL: fixtureRoot),
            timingLibraryLoader: FileSystemDFTTimingLibraryLoader(rootURL: fixtureRoot),
            constraintLoader: FileSystemDFTConstraintLoader(rootURL: fixtureRoot)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.artifacts.count == 3)
        #expect(result.payload.designDiff != nil)

        let reader = FixtureDFTArtifactReader(
            inputRoot: fixtureRoot,
            outputStore: store
        )
        try await DFTResultSemanticVerifier().validate(
            result,
            for: request,
            reading: reader
        )
        await #expect(throws: DFTResultSemanticValidationError.self) {
            try await DFTResultSemanticVerifier().validate(
                result,
                for: request,
                reading: TamperedDFTArtifactReader(
                    base: reader,
                    tamperedPath: try #require(
                        result.payload.transformedDesign?.artifact.path
                    )
                )
            )
        }
        await #expect(throws: DFTResultSemanticValidationError.self) {
            try await DFTResultSemanticVerifier().validate(
                result,
                for: request,
                reading: TamperedDFTArtifactReader(
                    base: reader,
                    tamperedPath: try #require(
                        result.artifacts.first {
                            $0.artifactID == "dft-scan-implementation"
                        }?.path
                    )
                )
            )
        }
        var detachedResult = result
        detachedResult.payload.scanImplementation?
            .chains[0].elements[0].scanInNetID = "detached-net"
        #expect(throws: DFTResultValidationError.self) {
            try DFTResultValidator().validate(detachedResult, for: request)
        }

        var mismatchedReference = request.design
        mismatchedReference.artifact = ArtifactReference(
            id: mismatchedReference.artifact.id,
            locator: mismatchedReference.artifact.locator,
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "0", count: 64)
            ),
            byteCount: mismatchedReference.artifact.byteCount,
            producer: mismatchedReference.artifact.producer
        )
        #expect(throws: DFTDesignLoaderError.self) {
            _ = try FileSystemDFTDesignLoader(rootURL: fixtureRoot).load(
                mismatchedReference
            )
        }
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

    @Test("native codec rejects standard formats it cannot serialize faithfully")
    func nativeCodecRejectsUnqualifiedStandardFormats() throws {
        let patternSet = DFTTestPatternSet(
            format: "JSON",
            seed: 7,
            faultUniverseDigest: String(repeating: "a", count: 64),
            patterns: [DFTTestPattern(id: "pattern-1", bits: "0101", faultIDs: ["f1"])]
        )
        let codec = DeterministicTestPatternCodec()

        for format in [DFTTestPatternFormat.stil, .wgl] {
            #expect(throws: DFTPatternFormatError.self) {
                _ = try codec.encode(patternSet, format: format)
            }
            #expect(throws: DFTPatternFormatError.self) {
                _ = try codec.decode(Data(), format: format)
            }
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
        let shellURL = URL(fileURLWithPath: "/bin/sh")
        let shellDigest = try SHA256ContentDigester().digest(
            data: Data(contentsOf: shellURL, options: .mappedIfSafe)
        ).hexadecimalValue
        let runner = ProcessDFTExternalToolRunner(
            descriptor: DFTExternalToolDescriptor(
                engineID: "external.atpg",
                implementationID: "fixture-process",
                implementationVersion: "1",
                binaryDigest: shellDigest
            ),
            executableURL: shellURL,
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
            engineID: stubExternalBinaryDigest,
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
        let stderrReference = try #require(
            persisted.artifacts.first {
                $0.artifactID == "dft-external-stderr"
            }
        )
        #expect(await store.data(for: stderrReference.path) == Data())

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
                engineID: stubExternalBinaryDigest,
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

    private func makeProcessSpecificATPGRequest() -> DFTRequest {
        makeRequest(
            operation: .atpg,
            scanArchitecture: scanArchitecture(),
            faultUniverse: DFTFaultUniverse(
                name: "process-faults",
                revision: "r1",
                faults: [DFTFault(
                    id: "m1-leakage",
                    family: .processSpecific,
                    location: "m1",
                    processFamily: "leakage"
                )],
                declaredBy: "fixture"
            ),
            atpgConfiguration: DFTATPGConfiguration(
                patternLength: 8,
                supportedProcessFamilies: ["leakage"]
            )
        )
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
                    sha256: String(repeating: "e", count: 64),
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
                    portBindings: [
                        GatePortBinding(portID: "port-clk", netID: "clk")
                    ],
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

    private func makeMemorySnapshot() -> LogicDesignSnapshot {
        let pins = [
            GatePin(id: "mem-clk", name: "CLK", direction: .input, netID: "clk"),
            GatePin(id: "mem-ce", name: "CE", direction: .input, netID: "ce"),
            GatePin(id: "mem-we", name: "WE", direction: .input, netID: "we"),
            GatePin(id: "mem-a0", name: "A0", direction: .input, netID: "a0"),
            GatePin(id: "mem-di0", name: "DI0", direction: .input, netID: "di0"),
            GatePin(id: "mem-do0", name: "DO0", direction: .output, netID: "do0"),
        ]
        let ports = [
            RTLPort(id: "port-clk", name: "scan_clk", direction: .input),
            RTLPort(id: "port-ce", name: "ce", direction: .input),
            RTLPort(id: "port-we", name: "we", direction: .input),
            RTLPort(id: "port-a0", name: "a0", direction: .input),
            RTLPort(id: "port-di0", name: "di0", direction: .input),
            RTLPort(id: "port-do0", name: "do0", direction: .output),
        ]
        let nets = [
            GateNet(id: "clk", name: "scan_clk", loadPinIDs: ["mem-clk"]),
            GateNet(id: "ce", name: "ce", loadPinIDs: ["mem-ce"]),
            GateNet(id: "we", name: "we", loadPinIDs: ["mem-we"]),
            GateNet(id: "a0", name: "a0", loadPinIDs: ["mem-a0"]),
            GateNet(id: "di0", name: "di0", loadPinIDs: ["mem-di0"]),
            GateNet(id: "do0", name: "do0", driverPinIDs: ["mem-do0"]),
        ]
        let module = GateModule(
            id: "module-top",
            name: "top",
            ports: ports,
            portBindings: zip(ports, nets).map {
                GatePortBinding(portID: $0.0.id, netID: $0.1.id)
            },
            cells: [GateCell(
                id: "cell-memory",
                type: "SRAM",
                instanceName: "u_mem",
                pins: pins
            )],
            nets: nets
        )
        return LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top"),
            gate: GateDesign(topModuleName: "top", modules: [module])
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
            portBindings: [
                GatePortBinding(portID: "port-d", netID: "net-d"),
                GatePortBinding(portID: "port-clk", netID: "net-clk"),
                GatePortBinding(portID: "port-reset", netID: "net-reset"),
                GatePortBinding(portID: "port-set", netID: "net-set"),
                GatePortBinding(portID: "port-q", netID: "net-q"),
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
            portBindings: [
                GatePortBinding(portID: "port-d", netID: "net-d"),
                GatePortBinding(portID: "port-en", netID: "net-en"),
                GatePortBinding(portID: "port-q", netID: "net-q"),
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
            portBindings: [
                GatePortBinding(portID: "port-a", netID: "net-a"),
                GatePortBinding(portID: "port-b", netID: "net-b"),
                GatePortBinding(portID: "port-y", netID: "net-y"),
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
            portBindings: [
                GatePortBinding(portID: "port-d", netID: "net-d"),
                GatePortBinding(portID: "port-clk", netID: "net-clk"),
                GatePortBinding(portID: "port-q", netID: "net-q"),
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

    private func makeCellLibraryManifest(
        scanCompressionMapping: DFTScanCompressionCellMapping? = nil
    ) -> DFTCellLibraryManifest {
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
                    testModePinName: "TM",
                    legalReplacementGroup: "scan-flops"
                )
            ],
            scanCompressionMapping: scanCompressionMapping,
            evidenceProvenance: DFTEvidenceProvenance(
                status: .corpusObserved,
                corpusRevision: "fixture-m2",
                notes: ["fixture binding only; no foundry trust decision"]
            )
        )
    }

    private func makeScanCompressionCellMapping(
        chainCount: Int
    ) -> DFTScanCompressionCellMapping {
        DFTScanCompressionCellMapping(
            decompressorCellType: "SCAN_DECOMPRESSOR",
            compactorCellType: "SCAN_COMPACTOR",
            decompressorInputPinNames: ["I"],
            decompressorOutputPinNames: (0..<chainCount).map { "O\($0)" },
            compactorInputPinNames: (0..<chainCount).map { "I\($0)" },
            compactorOutputPinNames: ["O"]
        )
    }

    private func makeLogicBISTCellMapping() -> DFTLogicBISTCellMapping {
        DFTLogicBISTCellMapping(
            artifact: testArtifact(
                artifactID: "logic-bist-cell-mapping",
                path: "logic-bist-cell-mapping.json",
                kind: .technology,
                format: .json,
                sha256: String(repeating: "9", count: 64),
                byteCount: 1,
                role: .input
            ),
            processID: "test-process",
            pdkDigest: String(repeating: "e", count: 64),
            controllerCellType: "LBIST_CTRL",
            inputMuxCellType: "LBIST_INPUT_MUX",
            responseCaptureCellType: "LBIST_RESPONSE_CAPTURE",
            responseCompactorCellType: "LBIST_RESPONSE_COMPACTOR",
            signatureRegisterCellType: "LBIST_SIGNATURE_REGISTER",
            prpgPolynomialTaps: [1, 3],
            misrPolynomialTaps: [1, 2],
            expectedSignature: "1010"
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
            manifestDigest: try DFTCellLibraryManifestCodec.digest(manifest),
            timingLibraryArtifact: testArtifact(
                artifactID: "cell-timing-library",
                path: "cell-timing.lib.json",
                kind: .technology,
                format: .json,
                sha256: String(repeating: "8", count: 64),
                byteCount: 1,
                role: .input
            )
        )
    }

    private func makeTimingLibrary(
        for manifest: DFTCellLibraryManifest
    ) throws -> TimingLibrary {
        let table = try TimingLUT.constant(0.1)
        let cells = Dictionary(uniqueKeysWithValues: manifest.bindings.map { binding in
            let arc = TimingArc(
                fromPin: binding.clockPinNames[0],
                toPin: binding.outputPinName,
                sense: .positiveUnate,
                delayRise: table,
                delayFall: table,
                transitionRise: table,
                transitionFall: table
            )
            var pinNames = Set([
                binding.dataPinName,
                binding.outputPinName,
                binding.scanInPinName,
                binding.scanEnablePinName,
            ])
            pinNames.formUnion(binding.clockPinNames)
            pinNames.formUnion(binding.resetPinNames)
            pinNames.formUnion(binding.setPinNames)
            if let testModePinName = binding.testModePinName {
                pinNames.insert(testModePinName)
            }
            let pins = pinNames.sorted().map { name in
                TimingPin(
                    name: name,
                    direction: name == binding.outputPinName ? .output : .input,
                    isClock: binding.clockPinNames.contains(name),
                    isData: name == binding.dataPinName
                )
            }
            let cell = TimingCell(
                name: binding.timingCellName ?? binding.scanCellType,
                pins: pins,
                arcs: [arc],
                sequentialModel: TimingSequentialModel(
                    dataPin: binding.dataPinName,
                    clockPin: binding.clockPinNames[0],
                    outputPin: binding.outputPinName,
                    clockToQ: arc
                )
            )
            return (cell.name, cell)
        })
        return TimingLibrary(name: "fixture-timing", cells: cells)
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
            implementationVersion: "1.0.0",
            binaryDigest: stubExternalBinaryDigest
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

private let stubExternalBinaryDigest = String(repeating: "f", count: 64)

private struct FixtureConstraintLoader: DFTConstraintLoading {
    var clockSignal = "scan_clk"

    func load(
        _ reference: DFTConstraintReference
    ) throws -> [TimingConstraintSet] {
        reference.modeIDs.map { modeID in
            TimingConstraintSet(
                modeID: modeID,
                clocks: [
                    TimingConstraintSet.Clock(
                        name: clockSignal,
                        source: clockSignal,
                        period: 10e-9
                    ),
                ],
                caseAnalyses: [
                    TimingConstraintSet.CaseAnalysis(
                        target: "scan_en",
                        value: .one
                    ),
                    TimingConstraintSet.CaseAnalysis(
                        target: "test_mode",
                        value: .one
                    ),
                ]
            )
        }
    }
}

private struct MissingModeConstraintLoader: DFTConstraintLoading {
    func load(
        _ reference: DFTConstraintReference
    ) throws -> [TimingConstraintSet] {
        guard let modeID = reference.modeIDs.first else {
            return []
        }
        return [
            TimingConstraintSet(
                modeID: modeID,
                clocks: [
                    TimingConstraintSet.Clock(
                        name: "scan_clk",
                        source: "scan_clk",
                        period: 10e-9
                    )
                ],
                caseAnalyses: [
                    TimingConstraintSet.CaseAnalysis(
                        target: "scan_en",
                        value: .one
                    ),
                    TimingConstraintSet.CaseAnalysis(
                        target: "test_mode",
                        value: .one
                    ),
                ]
            )
        ]
    }
}

private struct FixtureLogicBISTCellMappingLoader: DFTLogicBISTCellMappingLoading {
    func load(
        _ mapping: DFTLogicBISTCellMapping
    ) throws -> DFTLogicBISTCellMappingManifest {
        mapping.manifest
    }
}

private struct FixedLogicBISTCellMappingLoader: DFTLogicBISTCellMappingLoading {
    let manifest: DFTLogicBISTCellMappingManifest

    func load(
        _ mapping: DFTLogicBISTCellMapping
    ) throws -> DFTLogicBISTCellMappingManifest {
        _ = mapping
        return manifest
    }
}

private struct FixtureMemoryBISTCellMappingLoader: DFTMemoryBISTCellMappingLoading {
    func load(
        _ mapping: DFTMemoryBISTCellMapping
    ) throws -> DFTMemoryBISTCellMappingManifest {
        mapping.manifest
    }
}

private struct FixtureDFTArtifactReader: DFTArtifactReading {
    let inputRoot: URL
    let outputStore: InMemoryDFTArtifactStore

    func data(for reference: ArtifactReference) async throws -> Data {
        if reference.locator.role == .output {
            return try await outputStore.data(for: reference)
        }
        return try Data(
            contentsOf: inputRoot.appending(path: reference.path),
            options: .mappedIfSafe
        )
    }
}

private struct TamperedDFTArtifactReader: DFTArtifactReading {
    let base: any DFTArtifactReading
    let tamperedPath: String

    func data(for reference: ArtifactReference) async throws -> Data {
        var data = try await base.data(for: reference)
        if reference.path == tamperedPath {
            data.append(0)
        }
        return data
    }
}

private struct NonDetectingGateLevelSimulator: GateLevelSimulating {
    func simulate(
        snapshot: LogicDesignSnapshot,
        inputs: [String: Bool],
        fault: DFTFault?
    ) throws -> GateLevelSimulationResult {
        GateLevelSimulationResult(observedValues: ["out": false])
    }
}
