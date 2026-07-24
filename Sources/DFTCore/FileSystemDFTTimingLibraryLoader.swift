import CircuiteFoundation
import Foundation
import TimingCore

public struct FileSystemDFTTimingLibraryLoader: DFTTimingLibraryLoading {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public func load(_ reference: ArtifactReference) throws -> TimingLibrary {
        guard reference.format == .liberty || reference.format == .json else {
            throw DFTCellLibraryError.unsupportedFormat(reference.format)
        }
        let url: URL
        do {
            url = try DFTProjectArtifactResolver(rootURL: rootURL).resolve(
                reference.path
            )
        } catch {
            throw DFTCellLibraryError.invalidPath(reference.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw DFTCellLibraryError.readFailed(
                path: reference.path,
                message: error.localizedDescription
            )
        }
        guard UInt64(data.count) == reference.byteCount else {
            throw DFTCellLibraryError.byteCountMismatch(
                path: reference.path,
                expected: Int64(reference.byteCount),
                actual: Int64(data.count)
            )
        }
        let actualDigest = try SHA256ContentDigester().digest(data: data).hexadecimalValue
        guard actualDigest == reference.digest.hexadecimalValue else {
            throw DFTCellLibraryError.artifactDigestMismatch(
                path: reference.path,
                expected: reference.digest.hexadecimalValue,
                actual: actualDigest
            )
        }
        return try LibertyParser().parse(data)
    }
}
