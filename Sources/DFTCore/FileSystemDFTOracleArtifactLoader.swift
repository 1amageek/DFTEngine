import Foundation
import CircuiteFoundation

public actor FileSystemDFTOracleArtifactLoader: DFTOracleArtifactLoading {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public func load(_ reference: DFTArtifactReference) async throws -> Data {
        try Self.validate(reference)
        let expectedByteCount = reference.byteCount
        guard let expectedDigest = reference.sha256 else {
            throw DFTOracleArtifactError.missingDigest(reference.path)
        }
        let resolvedRoot = rootURL.resolvingSymlinksInPath()
        let url = rootURL.appending(path: reference.path).standardizedFileURL
        let resolvedURL = url.resolvingSymlinksInPath()
        guard Self.isInside(resolvedURL, root: resolvedRoot) else {
            throw DFTOracleArtifactError.invalidReference(reference.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: resolvedURL)
        } catch {
            throw DFTOracleArtifactError.readFailed(
                path: reference.path,
                message: error.localizedDescription
            )
        }
        if expectedByteCount != UInt64(data.count) {
            throw DFTOracleArtifactError.byteCountMismatch(
                path: reference.path,
                expected: Int64(expectedByteCount),
                actual: Int64(data.count)
            )
        }
        let actualDigest = DFTHasher().sha256(data: data)
        guard expectedDigest.caseInsensitiveCompare(actualDigest) == .orderedSame else {
            throw DFTOracleArtifactError.digestMismatch(
                path: reference.path,
                expected: expectedDigest,
                actual: actualDigest
            )
        }
        return data
    }

    private static func validate(_ reference: DFTArtifactReference) throws {
        guard let artifactID = reference.artifactID else {
            throw DFTOracleArtifactError.missingArtifactID(reference.path)
        }
        do {
            _ = try ArtifactID(rawValue: artifactID)
        } catch {
            throw DFTOracleArtifactError.invalidReference(reference.path)
        }
        guard isSafePath(reference.path) else {
            throw DFTOracleArtifactError.invalidReference(reference.path)
        }
        guard reference.sha256 != nil else {
            throw DFTOracleArtifactError.missingDigest(reference.path)
        }
        guard isSHA256(reference.sha256 ?? "") else {
            throw DFTOracleArtifactError.invalidDigest(reference.path)
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }

    private static func isSafePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return false
        }
        return !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }

    private static func isInside(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path == root.path || candidate.path.hasPrefix(rootPath)
    }
}
