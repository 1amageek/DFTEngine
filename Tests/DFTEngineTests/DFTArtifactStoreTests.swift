import DFTCore
import Foundation
import Testing
import CircuiteFoundation
import LogicIR

@Suite("DFT artifact stores")
struct DFTArtifactStoreTests {
    @Test("in-memory storage is immutable and idempotent")
    func inMemoryStoreIsImmutable() async throws {
        let store = InMemoryDFTArtifactStore()
        let original = DFTArtifactContent(
            artifactID: "artifact-a",
            fileName: "result.json",
            kind: .report,
            format: .json,
            data: Data("original".utf8)
        )
        let repeated = try await store.store(original, runID: "run-a")
        let idempotent = try await store.store(original, runID: "run-a")
        #expect(repeated == idempotent)

        let conflicting = DFTArtifactContent(
            artifactID: "artifact-a",
            fileName: "result.json",
            kind: .report,
            format: .json,
            data: Data("replacement".utf8)
        )
        do {
            _ = try await store.store(conflicting, runID: "run-a")
            Issue.record("An immutable artifact path must reject different bytes.")
        } catch let error as DFTArtifactStoreError {
            #expect(error == .artifactConflict("dft/runs/run-a/result.json"))
        }
    }

    @Test("file-system storage rejects replacement bytes")
    func fileSystemStoreIsImmutable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "dft-artifact-store-\(UUID().uuidString)")
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Could not remove artifact-store fixture: \(error.localizedDescription)")
            }
        }

        let store = FileSystemDFTArtifactStore(rootURL: root)
        let original = DFTArtifactContent(
            artifactID: "artifact-a",
            fileName: "result.json",
            kind: .report,
            format: .json,
            data: Data("original".utf8)
        )
        _ = try await store.store(original, runID: "run-a")

        let conflicting = DFTArtifactContent(
            artifactID: "artifact-a",
            fileName: "result.json",
            kind: .report,
            format: .json,
            data: Data("replacement".utf8)
        )
        do {
            _ = try await store.store(conflicting, runID: "run-a")
            Issue.record("An immutable artifact path must reject different bytes.")
        } catch let error as DFTArtifactStoreError {
            #expect(error == .artifactConflict("dft/runs/run-a/result.json"))
        }
    }

    @Test("artifact stores reject invalid artifact identities")
    func artifactIdentityIsRequired() async throws {
        let store = InMemoryDFTArtifactStore()
        let content = DFTArtifactContent(
            artifactID: " invalid ",
            fileName: "result.json",
            kind: .report,
            format: .json,
            data: Data())

        do {
            _ = try await store.store(content, runID: "run-a")
            Issue.record("Artifact stores must reject invalid Foundation artifact IDs.")
        } catch let error as DFTArtifactStoreError {
            #expect(error == .invalidArtifactID(" invalid "))
        }
    }

    @Test("file-system storage rejects a symlink that escapes the root")
    func fileSystemStoreRejectsEscapedSymlink() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "dft-artifact-root-\(UUID().uuidString)")
        let outside = FileManager.default.temporaryDirectory
            .appending(path: "dft-artifact-outside-\(UUID().uuidString)")
        defer {
            for url in [root, outside] {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    Issue.record("Could not remove symlink fixture: \(error.localizedDescription)")
                }
            }
        }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "dft"),
            withDestinationURL: outside
        )

        let content = DFTArtifactContent(
            artifactID: "artifact-a",
            fileName: "result.json",
            kind: .report,
            format: .json,
            data: Data("result".utf8)
        )
        do {
            _ = try await FileSystemDFTArtifactStore(rootURL: root).store(
                content,
                runID: "run-a"
            )
            Issue.record("Artifact storage must reject a path that escapes its root through a symlink.")
        } catch let error as DFTArtifactStoreError {
            #expect(error == .pathOutsideRoot("dft/runs/run-a/result.json"))
        }
    }

    @Test("file-system input loaders reject a symlink that escapes the root")
    func fileSystemInputLoaderRejectsEscapedSymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "dft-input-root-\(UUID().uuidString)")
        let outside = FileManager.default.temporaryDirectory
            .appending(path: "dft-input-outside-\(UUID().uuidString)")
        defer {
            for url in [root, outside] {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    Issue.record(
                        "Could not remove input-loader fixture: \(error.localizedDescription)"
                    )
                }
            }
        }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        let outsideDesign = outside.appending(path: "design.json")
        try Data("{}".utf8).write(to: outsideDesign)
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "design.json"),
            withDestinationURL: outsideDesign
        )
        let artifact = testArtifact(
            artifactID: "design",
            path: "design.json",
            kind: .netlist,
            format: .json,
            sha256: String(repeating: "0", count: 64),
            byteCount: 2,
            role: .input
        )
        let reference = LogicDesignReference(
            artifact: artifact,
            topDesignName: "top",
            designDigest: String(repeating: "1", count: 64)
        )

        #expect(throws: DFTDesignLoaderError.invalidPath("design.json")) {
            _ = try FileSystemDFTDesignLoader(rootURL: root).load(reference)
        }
    }
}
