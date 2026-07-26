import CircuiteFoundation
import Foundation

public struct FileSystemDFTMemoryBISTCellMappingLoader: DFTMemoryBISTCellMappingLoading {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public func load(
        _ mapping: DFTMemoryBISTCellMapping
    ) throws -> DFTMemoryBISTCellMappingManifest {
        let path = mapping.artifact.path
        guard mapping.artifact.format == .json else {
            throw DFTMemoryBISTCellMappingError.invalidPath(path)
        }
        let url: URL
        do {
            url = try DFTProjectArtifactResolver(rootURL: rootURL).resolve(path)
        } catch {
            throw DFTMemoryBISTCellMappingError.invalidPath(path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw DFTMemoryBISTCellMappingError.readFailed(error.localizedDescription)
        }
        guard UInt64(data.count) == mapping.artifact.byteCount,
              try SHA256ContentDigester().digest(data: data) == mapping.artifact.digest else {
            throw DFTMemoryBISTCellMappingError.identityMismatch(path)
        }
        do {
            return try JSONDecoder().decode(
                DFTMemoryBISTCellMappingManifest.self,
                from: data
            )
        } catch {
            throw DFTMemoryBISTCellMappingError.decodeFailed(error.localizedDescription)
        }
    }
}
