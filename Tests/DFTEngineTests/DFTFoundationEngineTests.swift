import CircuiteFoundation
import DFTCore
import DFTEngine
import Foundation
import LogicIR
import PDKCore
import Testing
import TimingCore
import XcircuitePackage

@Suite("DFT Foundation execution")
struct DFTFoundationEngineTests {
    @Test("Foundation adapter records verified inputs and execution provenance")
    func foundationAdapterPreservesProvenance() async throws {
        let input = XcircuiteFileReference(
            artifactID: "design-input",
            path: "design.json",
            kind: .netlist,
            format: .json,
            sha256: String(repeating: "a", count: 64),
            byteCount: 10
        )
        let request = DFTRequest(
            runID: "foundation-run",
            inputs: [input],
            design: LogicDesignReference(
                artifact: input,
                topDesignName: "top",
                designDigest: String(repeating: "b", count: 64)
            ),
            constraints: TimingConstraintReference(
                artifact: XcircuiteFileReference(
                    artifactID: "constraints",
                    path: "constraints.sdc",
                    kind: .constraint,
                    format: .sdc,
                    sha256: String(repeating: "c", count: 64),
                    byteCount: 4
                ),
                modeIDs: ["test"]
            ),
            pdk: PDKReference(
                manifest: XcircuiteFileReference(
                    artifactID: "pdk",
                    path: "pdk.json",
                    kind: .technology,
                    format: .json,
                    sha256: String(repeating: "d", count: 64),
                    byteCount: 4
                ),
                processID: "fixture-process",
                version: "1",
                digest: String(repeating: "e", count: 64)
            ),
            operation: .atpg
        )
        let timestamp = Date(timeIntervalSince1970: 100)
        let result = XcircuiteEngineResultEnvelope(
            schemaVersion: DFTRequest.currentSchemaVersion,
            runID: request.runID,
            status: .blocked,
            metadata: XcircuiteEngineExecutionMetadata(
                engineID: "dft.atpg",
                implementationID: "fixture",
                implementationVersion: "1",
                startedAt: timestamp,
                completedAt: timestamp.addingTimeInterval(1),
                seed: 7
            ),
            payload: DFTPayload(transformedDesign: nil, faultCoverage: nil)
        )

        let evidence = try await DFTFoundationEngine(
            legacyEngine: StubDFTEngine(result: result)
        ).execute(request)

        #expect(evidence.evidence.provenance.inputs.count == 1)
        #expect(evidence.evidence.provenance.inputs[0].id.rawValue == "design-input")
        #expect(evidence.evidence.provenance.producer.identifier == "dft.atpg")
        #expect(evidence.evidence.provenance.producer.build == "fixture")
        #expect(evidence.evidence.provenance.randomSeed == 7)
        #expect(evidence.evidence.provenance.designRevision?.hexadecimalValue == String(repeating: "b", count: 64))
        #expect(evidence.evidence.provenance.configurationDigest?.algorithm == .sha256)
    }
}

private struct StubDFTEngine: DFTEngineExecuting {
    let result: XcircuiteEngineResultEnvelope<DFTPayload>

    func execute(
        _ request: DFTRequest
    ) async throws -> XcircuiteEngineResultEnvelope<DFTPayload> {
        result
    }
}
