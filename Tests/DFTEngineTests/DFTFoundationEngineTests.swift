import CircuiteFoundation
import DFTCore
import DFTEngine
import Foundation
import LogicIR
import PDKCore
import Testing

@Suite("DFT Foundation execution")
struct DFTFoundationEngineTests {
    @Test("Foundation engine executes the DFT domain protocol directly")
    func foundationEngineExecutesDomainProtocol() async throws {
        let input = testArtifact(
            artifactID: "design-input",
            path: "design.json",
            kind: .netlist,
            format: .json,
            sha256: String(repeating: "a", count: 64),
            byteCount: 10,
            role: .input
        )
        let request = DFTRequest(
            runID: "foundation-run",
            inputs: [input],
            design: LogicDesignReference(
                artifact: input.locator,
                topDesignName: "top",
                designDigest: String(repeating: "b", count: 64)
            ),
            constraints: DFTConstraintReference(
                artifact: testArtifact(
                    artifactID: "constraints",
                    path: "constraints.sdc",
                    kind: .constraint,
                    format: .sdc,
                    sha256: String(repeating: "c", count: 64),
                    byteCount: 4,
                    role: .input
                ),
                modeIDs: ["test"]
            ),
            pdk: PDKReference(
                manifest: testArtifact(
                    artifactID: "pdk",
                    path: "pdk.json",
                    kind: .technology,
                    format: .json,
                    sha256: String(repeating: "d", count: 64),
                    byteCount: 4,
                    role: .input
                ),
                processID: "fixture-process",
                version: "1",
                digest: String(repeating: "e", count: 64)
            ),
            operation: .atpg
        )
        let timestamp = Date(timeIntervalSince1970: 100)
        let result = DFTResult(
            schemaVersion: DFTRequest.currentSchemaVersion,
            runID: request.runID,
            status: .blocked,
            metadata: DFTExecutionMetadata(
                engineID: "dft.atpg",
                implementationID: "fixture",
                implementationVersion: "1",
                startedAt: timestamp,
                completedAt: timestamp.addingTimeInterval(1),
                seed: 7
            ),
            payload: DFTPayload(transformedDesign: nil, faultCoverage: nil)
        )

        let executed = try await DFTFoundationEngine(
            engine: StubDFTEngine(result: result)
        ).execute(request)

        #expect(executed == result)
        #expect(executed.metadata.engineID == "dft.atpg")
        #expect(executed.metadata.seed == 7)
    }
}

private struct StubDFTEngine: DFTEngineExecuting {
    let result: DFTResult

    func execute(
        _ request: DFTRequest
    ) async throws -> DFTResult {
        result
    }
}
