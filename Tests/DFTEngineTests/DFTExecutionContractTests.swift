import CircuiteFoundation
import DFTCore
import DFTEngine
import Foundation
import LogicIR
import PDKCore
import Testing

@Suite("DFT execution contract")
struct DFTExecutionContractTests {
    @Test("DFT design diff contains raw changes but no flow review state")
    func designDiffExcludesFlowReviewState() throws {
        let diff = DFTDesignDiff(
            runID: "foundation-run",
            title: "Insert scan",
            actor: "DFTEngine/native",
            changes: [],
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let encoded = try DFTArtifactJSONEncoder().encode(diff)
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        #expect(object["reviewState"] == nil)
        #expect(object["schemaVersion"] as? Int == DFTDesignDiff.currentSchemaVersion)

        var unsupportedObject = object
        unsupportedObject["schemaVersion"] = 1
        let unsupportedData = try JSONSerialization.data(withJSONObject: unsupportedObject)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(DFTDesignDiff.self, from: unsupportedData)
        }
    }

    @Test("DFT implementation executes the Foundation Engine contract directly")
    func implementationExecutesFoundationEngineContract() async throws {
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
                artifact: input,
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
            provenance: try DFTExecutionSupport.provenance(
                engineID: "dft.atpg",
                implementationID: "fixture",
                implementationVersion: "1",
                startedAt: timestamp,
                completedAt: timestamp.addingTimeInterval(1),
                seed: 7
            ),
            payload: DFTPayload(transformedDesign: nil, faultCoverage: nil)
        )

        let executed = try await StubDFTEngine(result: result).execute(request)

        #expect(executed == result)
        #expect(executed.provenance.producer.identifier == "dft.atpg")
        #expect(executed.provenance.randomSeed == 7)
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
