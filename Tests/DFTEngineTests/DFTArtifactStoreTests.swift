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

    @Test("batch storage validates every artifact before publication")
    func batchStorageIsAtomic() async throws {
        let store = InMemoryDFTArtifactStore()
        let first = DFTArtifactContent(
            artifactID: "artifact-a",
            fileName: "a.json",
            kind: .report,
            format: .json,
            data: Data("a".utf8)
        )
        let second = DFTArtifactContent(
            artifactID: "artifact-b",
            fileName: "b.json",
            kind: .report,
            format: .json,
            data: Data("b".utf8)
        )
        let references = try await store.storeBatch(
            [first, second],
            runID: "run-batch"
        )
        #expect(references.count == 2)
        let paths = try references.map {
            try $0.requireLocalRelativePath().stringValue
        }
        #expect(Set(paths).count == 2)
        #expect(paths.allSatisfy { $0.contains("/batch-") })

        var conflicting = second
        conflicting.data = Data("replacement".utf8)
        await #expect(throws: DFTArtifactStoreError.self) {
            _ = try await store.storeBatch(
                [first, conflicting],
                runID: "run-batch"
            )
        }
        #expect(
            try await store.data(for: references[0]) == first.data
        )
        #expect(
            try await store.data(for: references[1]) == second.data
        )

        var duplicateIdentity = second
        duplicateIdentity.artifactID = first.artifactID
        await #expect(throws: DFTArtifactStoreError.self) {
            _ = try await store.storeBatch(
                [first, duplicateIdentity],
                runID: "run-duplicate"
            )
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
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )

        let store = try FileSystemDFTArtifactStore(rootURL: root)
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

    @Test("file-system batch storage publishes one immutable directory")
    func fileSystemBatchStoreIsAtomicAndImmutable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "dft-artifact-batch-\(UUID().uuidString)")
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record(
                    "Could not remove batch-store fixture: \(error.localizedDescription)"
                )
            }
        }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        let store = try FileSystemDFTArtifactStore(rootURL: root)
        let contents = [
            DFTArtifactContent(
                artifactID: "batch-a",
                fileName: "a.json",
                kind: .report,
                format: .json,
                data: Data("a".utf8)
            ),
            DFTArtifactContent(
                artifactID: "batch-b",
                fileName: "b.json",
                kind: .report,
                format: .json,
                data: Data("b".utf8)
            ),
        ]

        let references = try await store.storeBatch(
            contents,
            runID: "run-batch"
        )
        #expect(references.count == contents.count)
        let parentPaths = try references.map {
            try $0.requireLocalRelativePath().segments
                .dropLast()
                .joined(separator: "/")
        }
        #expect(Set(parentPaths).count == 1)
        for (content, reference) in zip(contents, references) {
            #expect(try await store.data(for: reference) == content.data)
        }
        #expect(
            try await store.storeBatch(contents, runID: "run-batch")
                == references
        )
        let concurrentStore = try FileSystemDFTArtifactStore(rootURL: root)
        async let firstPublication = store.storeBatch(
            contents,
            runID: "run-concurrent"
        )
        async let secondPublication = concurrentStore.storeBatch(
            contents,
            runID: "run-concurrent"
        )
        let concurrentReferences = try await (
            firstPublication,
            secondPublication
        )
        #expect(concurrentReferences.0 == concurrentReferences.1)

        var conflicting = contents
        conflicting[1].data = Data("replacement".utf8)
        await #expect(throws: DFTArtifactStoreError.self) {
            _ = try await store.storeBatch(
                conflicting,
                runID: "run-batch"
            )
        }
        #expect(try await store.data(for: references[1]) == contents[1].data)
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
    func fileSystemInputLoaderRejectsEscapedSymlink() async throws {
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
        let binding = testArtifactBinding(
            artifactID: "design",
            path: "design.json",
            kind: .netlist,
            format: .json,
            sha256: String(repeating: "0", count: 64),
            byteCount: 2,
            role: .input
        )
        let reference = LogicDesignReference(
            artifact: binding.reference,
            topDesignName: "top",
            designDigest: String(repeating: "1", count: 64)
        )

        let store = try FileSystemDFTArtifactStore(rootURL: root)
        await #expect(throws: DFTDesignLoaderError.self) {
            _ = try await FileSystemDFTDesignLoader(
                artifactReader: store
            ).load(reference, binding: binding)
        }
    }
}
