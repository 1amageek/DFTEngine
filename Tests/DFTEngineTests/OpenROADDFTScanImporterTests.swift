import CircuiteFoundation
@testable import DFTCLIKit
import DFTCore
@testable import DFTExternalTools
import Foundation
import PDKCore
import Testing

@Suite("OpenROAD DFT scan importer")
struct OpenROADDFTScanImporterTests {
    @Test("retained Verilog and ScanDEF become a canonical scan implementation")
    func importsRetainedScanEvidence() async throws {
        let store = InMemoryDFTArtifactStore()
        let request = try await makeRequest(store: store)

        let result = try await OpenROADDFTScanImporter(
            artifactReader: store,
            artifactStore: store
        ).importScan(request)

        #expect(result.runID == request.runID)
        #expect(result.producer == request.producer)
        #expect(result.processID == "sky130A")
        #expect(result.pdkDigest == String(repeating: "b", count: 64))
        #expect(result.inputs == [
            request.sourceNetlistArtifact,
            request.transformedNetlistArtifact,
            request.scanDEFArtifact,
            request.cellLibraryArtifact,
            request.executionEvidenceArtifact,
        ])
        #expect(
            result.sourceDesign.designDigest
                != result.transformedDesign.designDigest
        )
        #expect(
            result.scanImplementation.transformedDesignDigest
                == result.transformedDesign.designDigest
        )
        let implementationData = try await store.data(
            for: result.scanImplementation.artifact
        )
        let implementation = try JSONDecoder().decode(
            DFTScanImplementation.self,
            from: implementationData
        )
        #expect(implementation.chains.count == 1)
        #expect(implementation.chains[0].scanInSignal == "scan_in")
        #expect(implementation.chains[0].scanOutSignal == "q")
        #expect(
            implementation.chains[0].elements[0].outputNetID
                == implementation.chains[0].elements[1].scanInNetID
        )
        #expect(
            DFTScanImplementationValidator()
                .validationIssues(in: implementation)
                .isEmpty
        )
        #expect(result.artifacts.count == 4)
        for artifact in result.artifacts {
            #expect(try await !store.data(for: artifact).isEmpty)
        }
    }

    @Test("tampered ScanDEF fails before canonical import")
    func rejectsTamperedScanDEF() async throws {
        let store = InMemoryDFTArtifactStore()
        var request = try await makeRequest(store: store)
        request.scanDEFArtifact = ArtifactReference(
            id: request.scanDEFArtifact.id,
            locator: request.scanDEFArtifact.locator,
            digest: request.scanDEFArtifact.digest,
            byteCount: request.scanDEFArtifact.byteCount + 1,
            producer: request.scanDEFArtifact.producer
        )

        await #expect(throws: OpenROADDFTScanImportError.self) {
            _ = try await OpenROADDFTScanImporter(
                artifactReader: store,
                artifactStore: store
            ).importScan(request)
        }
    }

    @Test("ScanDEF order must match transformed Verilog connectivity")
    func rejectsDisconnectedScanOrder() async throws {
        let store = InMemoryDFTArtifactStore()
        var request = try await makeRequest(store: store)
        request.scanDEFArtifact = try await store.store(
            DFTArtifactContent(
                artifactID: "openroad-disconnected-scandef",
                fileName: "disconnected-scan.def",
                kind: .netlist,
                format: .raw,
                data: Data(
                    """
                    VERSION 5.8 ;
                    DESIGN scan_dut ;
                    SCANCHAINS 1 ;
                    - chain_0
                    + START PIN scan_in
                    + FLOATING
                      u_scan_1 ( IN SCD ) ( OUT Q )
                      u_scan_0 ( IN SCD ) ( OUT Q )
                    + PARTITION clk
                    + STOP PIN q ;
                    END SCANCHAINS
                    END DESIGN
                    """.utf8
                )
            ),
            runID: request.runID
        )

        await #expect(throws: OpenROADDFTScanImportError.self) {
            _ = try await OpenROADDFTScanImporter(
                artifactReader: store,
                artifactStore: store
            ).importScan(request)
        }
    }

    @Test("ScanDEF parser rejects instance endpoints at the hosted boundary")
    func rejectsNonTopLevelChainEndpoint() throws {
        let data = Data(
            """
            VERSION 5.8 ;
            DESIGN scan_dut ;
            SCANCHAINS 1 ;
            - chain_0
            + START u_scan_0 SCD
            + FLOATING
              u_scan_0 ( IN SCD ) ( OUT Q )
            + PARTITION clk
            + STOP PIN q ;
            END SCANCHAINS
            END DESIGN
            """.utf8
        )

        #expect(throws: OpenROADDFTScanImportError.self) {
            _ = try OpenROADScanDEFParser().parse(data)
        }
    }

    @Test("ScanDEF PIN endpoints must resolve to real top-level ports")
    func rejectsInternalNetReportedAsPin() async throws {
        let store = InMemoryDFTArtifactStore()
        var request = try await makeRequest(store: store)
        request.scanDEFArtifact = try await store.store(
            DFTArtifactContent(
                artifactID: "openroad-internal-endpoint-scandef",
                fileName: "internal-endpoint-scan.def",
                kind: .netlist,
                format: .raw,
                data: Data(
                    """
                    VERSION 5.8 ;
                    DESIGN scan_dut ;
                    SCANCHAINS 1 ;
                    - chain_0
                    + START PIN scan_in
                    + FLOATING
                      u_scan_0 ( IN SCD ) ( OUT Q )
                    + PARTITION clk
                    + STOP PIN q0 ;
                    END SCANCHAINS
                    END DESIGN
                    """.utf8
                )
            ),
            runID: request.runID
        )

        await #expect(throws: OpenROADDFTScanImportError.self) {
            _ = try await OpenROADDFTScanImporter(
                artifactReader: store,
                artifactStore: store
            ).importScan(request)
        }
    }

    @Test("every source scan candidate must appear exactly once in ScanDEF")
    func rejectsOmittedSourceScanCandidate() async throws {
        let store = InMemoryDFTArtifactStore()
        var request = try await makeRequest(store: store)
        request.sourceNetlistArtifact = try await store.store(
            DFTArtifactContent(
                artifactID: "openroad-source-with-orphan",
                fileName: "source-with-orphan.v",
                kind: .netlist,
                format: .verilog,
                data: Data(
                    """
                    module scan_dut(clk,d,test_mode,scan_enable,scan_in,q,orphan_q);
                      sky130_fd_sc_hd__dfxtp_1 u_scan_0(.D(d),.Q(q0),.CLK(clk));
                      sky130_fd_sc_hd__dfxtp_1 u_scan_1(.D(q0),.Q(q),.CLK(clk));
                      sky130_fd_sc_hd__dfxtp_1 u_scan_orphan(.D(d),.Q(orphan_q),.CLK(clk));
                    endmodule
                    """.utf8
                )
            ),
            runID: request.runID
        )
        request.transformedNetlistArtifact = try await store.store(
            DFTArtifactContent(
                artifactID: "openroad-transformed-with-orphan",
                fileName: "transformed-with-orphan.v",
                kind: .netlist,
                format: .verilog,
                data: Data(
                    """
                    module scan_dut(clk,d,test_mode,scan_enable,scan_in,q,orphan_q);
                      sky130_fd_sc_hd__sdfxtp_1 u_scan_0(.D(d),.Q(q0),.SCD(scan_in),.SCE(scan_enable),.CLK(clk));
                      sky130_fd_sc_hd__sdfxtp_1 u_scan_1(.D(q0),.Q(q),.SCD(q0),.SCE(scan_enable),.CLK(clk));
                      sky130_fd_sc_hd__sdfxtp_1 u_scan_orphan(.D(d),.Q(orphan_q),.SCD(d),.SCE(scan_enable),.CLK(clk));
                    endmodule
                    """.utf8
                )
            ),
            runID: request.runID
        )

        await #expect(throws: OpenROADDFTScanImportError.self) {
            _ = try await OpenROADDFTScanImporter(
                artifactReader: store,
                artifactStore: store
            ).importScan(request)
        }
    }

    @Test("CLI imports retained OpenROAD scan evidence without semantic glue")
    func importsThroughCLI() async throws {
        let root = try temporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let store = FileSystemDFTArtifactStore(rootURL: root)
        let request = try await makeRequest(store: store)
        let requestURL = root.appending(path: "openroad-import-request.json")
        let resultURL = root.appending(path: "openroad-import-result.json")
        try DFTArtifactJSONEncoder().encode(request).write(
            to: requestURL,
            options: .atomic
        )

        let exitCode = try await DFTCLICommand().run(arguments: [
            "import-openroad-scan",
            "--request", requestURL.path,
            "--output-dir", root.path,
            "--result", resultURL.path,
        ])

        #expect(exitCode == 0)
        let result = try JSONDecoder().decode(
            OpenROADDFTScanImportResult.self,
            from: Data(contentsOf: resultURL)
        )
        #expect(result.processID == "sky130A")
        #expect(result.artifacts.count == 4)
    }

    @Test("CLI composes realized scan ATPG without reinterpreting ScanDEF")
    func composesRealizedScanATPGThroughCLI() async throws {
        let root = try temporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let store = FileSystemDFTArtifactStore(rootURL: root)
        let importRequest = try await makeRequest(store: store)
        let importResult = try await OpenROADDFTScanImporter(
            artifactReader: store,
            artifactStore: store
        ).importScan(importRequest)
        let importResultURL = root.appending(path: "openroad-import-result.json")
        let configurationURL = root.appending(path: "atpg-configuration.json")
        let requestURL = root.appending(path: "atpg-request.json")
        try DFTArtifactJSONEncoder().encode(importResult).write(
            to: importResultURL,
            options: .atomic
        )
        let constraint = try fixtureArtifact(
            id: "test-constraint",
            path: "constraints.sdc",
            kind: .constraint,
            format: .sdc,
            digest: String(repeating: "c", count: 64)
        )
        let pdkManifest = try fixtureArtifact(
            id: "test-pdk",
            path: "pdk.json",
            kind: .technology,
            format: .json,
            digest: importResult.pdkDigest
        )
        let timingLibrary = try fixtureArtifact(
            id: "test-timing",
            path: "timing.lib",
            kind: .timingLibrary,
            format: .liberty,
            digest: String(repeating: "d", count: 64)
        )
        let cellLibraryManifest = try DFTCellLibraryManifestCodec.decode(
            await store.data(for: importRequest.cellLibraryArtifact)
        )
        let cellLibrary = DFTCellLibraryReference(
            artifact: importRequest.cellLibraryArtifact,
            processID: importResult.processID,
            version: "test",
            manifestDigest: try DFTCellLibraryManifestCodec.digest(
                cellLibraryManifest
            ),
            timingLibraryArtifact: timingLibrary
        )
        let configuration = DFTRealizedScanATPGRequestConfiguration(
            runID: "openroad-atpg-test",
            constraints: DFTConstraintReference(
                artifact: constraint,
                modeIDs: ["scan"]
            ),
            pdk: PDKReference(
                manifest: pdkManifest,
                processID: importResult.processID,
                version: "test",
                digest: importResult.pdkDigest
            ),
            cellLibrary: cellLibrary,
            clocks: [
                DFTScanClock(
                    id: "scan-clock",
                    signalName: "clk",
                    periodNanoseconds: 10
                ),
            ],
            domainClockIDs: ["clk": "scan-clock"],
            atpg: DFTATPGConfiguration(
                maximumPatternCount: 64,
                patternLength: 16,
                faultSource: .gateLevel,
                maximumExhaustiveInputCount: 8
            )
        )
        try DFTArtifactJSONEncoder().encode(configuration).write(
            to: configurationURL,
            options: .atomic
        )

        let exitCode = try await DFTCLICommand().run(arguments: [
            "compose-atpg-request",
            "--import-result", importResultURL.path,
            "--configuration", configurationURL.path,
            "--output-dir", root.path,
            "--result", requestURL.path,
        ])

        #expect(exitCode == 0)
        let request = try JSONDecoder().decode(
            DFTRequest.self,
            from: Data(contentsOf: requestURL)
        )
        #expect(request.operation == .atpg)
        #expect(request.design == importResult.transformedDesign)
        #expect(request.cellLibrary == cellLibrary)
        #expect(request.scanImplementation == importResult.scanImplementation)
        #expect(request.scanArchitecture?.domains == [
            DFTScanDomain(
                id: "clk",
                clockID: "scan-clock",
                chainCount: 1,
                estimatedElementCount: 2,
                maximumChainLength: 2
            ),
        ])

        var incompleteMapping = configuration
        incompleteMapping.domainClockIDs = [:]
        await #expect(
            throws: DFTRealizedScanATPGRequestBuilderError.self
        ) {
            _ = try await DefaultDFTRealizedScanATPGRequestBuilder(
                artifactReader: store
            ).build(
                importResult: importResult,
                configuration: incompleteMapping
            )
        }

        var lossyFaultSource = configuration
        lossyFaultSource.atpg.faultSource = .declaredUniverse
        await #expect(
            throws: DFTRealizedScanATPGRequestBuilderError.self
        ) {
            _ = try await DefaultDFTRealizedScanATPGRequestBuilder(
                artifactReader: store
            ).build(
                importResult: importResult,
                configuration: lossyFaultSource
            )
        }

        var detachedCellLibrary = configuration
        detachedCellLibrary.cellLibrary.artifact = try fixtureArtifact(
            id: "detached-cell-library",
            path: "detached-cell-library.json",
            kind: .technology,
            format: .json,
            digest: String(repeating: "e", count: 64)
        )
        await #expect(
            throws: DFTRealizedScanATPGRequestBuilderError.self
        ) {
            _ = try await DefaultDFTRealizedScanATPGRequestBuilder(
                artifactReader: store
            ).build(
                importResult: importResult,
                configuration: detachedCellLibrary
            )
        }
    }

    private func makeRequest(
        store: any DFTArtifactStoring
    ) async throws -> OpenROADDFTScanImportRequest {
        let runID = "openroad-import-test"
        let source = try await store.store(
            DFTArtifactContent(
                artifactID: "openroad-source-netlist",
                fileName: "source.v",
                kind: .netlist,
                format: .verilog,
                data: Data(
                    """
                    module scan_dut(clk,d,test_mode,scan_enable,scan_in,q);
                      sky130_fd_sc_hd__dfxtp_1 u_scan_0(.D(d),.Q(q0),.CLK(clk));
                      sky130_fd_sc_hd__dfxtp_1 u_scan_1(.D(q0),.Q(q),.CLK(clk));
                    endmodule
                    """.utf8
                )
            ),
            runID: runID
        )
        let transformed = try await store.store(
            DFTArtifactContent(
                artifactID: "openroad-transformed-netlist",
                fileName: "transformed.v",
                kind: .netlist,
                format: .verilog,
                data: Data(
                    """
                    module scan_dut(clk,d,test_mode,scan_enable,scan_in,q);
                      sky130_fd_sc_hd__sdfxtp_1 u_scan_0(.D(d),.Q(q0),.SCD(scan_in),.SCE(scan_enable),.CLK(clk));
                      sky130_fd_sc_hd__sdfxtp_1 u_scan_1(.D(q0),.Q(q),.SCD(q0),.SCE(scan_enable),.CLK(clk));
                    endmodule
                    """.utf8
                )
            ),
            runID: runID
        )
        let scanDEF = try await store.store(
            DFTArtifactContent(
                artifactID: "openroad-scandef",
                fileName: "scan.def",
                kind: .netlist,
                format: .raw,
                data: Data(
                    """
                    VERSION 5.8 ;
                    DESIGN scan_dut ;
                    SCANCHAINS 1 ;
                    - chain_0
                    + START PIN scan_in
                    + FLOATING
                      u_scan_0 ( IN SCD ) ( OUT Q )
                      u_scan_1 ( IN SCD ) ( OUT Q )
                    + PARTITION clk
                    + STOP PIN q ;
                    END SCANCHAINS
                    END DESIGN
                    """.utf8
                )
            ),
            runID: runID
        )
        let manifest = DFTCellLibraryManifest(
            processID: "sky130A",
            version: "test",
            pdkDigest: String(repeating: "b", count: 64),
            bindings: [
                DFTCellLibraryBinding(
                    bindingID: "sky130-rising-scan",
                    functionalCellType: "sky130_fd_sc_hd__dfxtp_1",
                    scanCellType: "sky130_fd_sc_hd__sdfxtp_1",
                    dataPinName: "D",
                    outputPinName: "Q",
                    clockPinNames: ["CLK"],
                    scanInPinName: "SCD",
                    scanEnablePinName: "SCE",
                    testModePinName: nil
                ),
            ],
            evidenceProvenance: DFTEvidenceProvenance(
                status: .corpusObserved,
                processID: "sky130A",
                pdkDigest: String(repeating: "b", count: 64)
            )
        )
        let cellLibrary = try await store.store(
            DFTArtifactContent(
                artifactID: "openroad-cell-library",
                fileName: "cell-library.json",
                kind: .technology,
                format: .json,
                data: try DFTCellLibraryManifestCodec.encode(manifest)
            ),
            runID: runID
        )
        let executionEvidence = try await store.store(
            DFTArtifactContent(
                artifactID: "openroad-execution-evidence",
                fileName: "openroad.log",
                kind: .evidence,
                format: .raw,
                data: Data("OPENROAD_DFT_COMPLETE\n".utf8)
            ),
            runID: runID
        )
        return OpenROADDFTScanImportRequest(
            runID: runID,
            architectureName: "sky130_scan",
            topModule: "scan_dut",
            scanEnableSignal: "scan_enable",
            testModeSignal: "test_mode",
            sourceNetlistArtifact: source,
            transformedNetlistArtifact: transformed,
            scanDEFArtifact: scanDEF,
            cellLibraryArtifact: cellLibrary,
            executionEvidenceArtifact: executionEvidence,
            producer: DFTExternalToolDescriptor(
                engineID: "dft.scan-insertion",
                implementationID: "openroad",
                implementationVersion: "test",
                binaryDigest: String(repeating: "a", count: 64)
            )
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "dft-openroad-import-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false
        )
        return url
    }

    private func fixtureArtifact(
        id: String,
        path: String,
        kind: ArtifactKind,
        format: ArtifactFormat,
        digest: String
    ) throws -> ArtifactReference {
        ArtifactReference(
            id: try ArtifactID(rawValue: id),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: path
                ),
                role: .input,
                kind: kind,
                format: format
            ),
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: digest
            ),
            byteCount: 1
        )
    }

    private func removeTemporaryDirectory(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Failed to remove OpenROAD import test directory: \(error)")
        }
    }
}
