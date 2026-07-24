import CircuiteFoundation
import Foundation

public struct FileSystemDFTLogicBISTCellMappingLoader: DFTLogicBISTCellMappingLoading {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public func load(
        _ mapping: DFTLogicBISTCellMapping
    ) throws -> DFTLogicBISTCellMappingManifest {
        let path = mapping.artifact.path
        guard mapping.artifact.format == .json else {
            throw DFTLogicBISTCellMappingError.invalidPath(path)
        }
        let url: URL
        do {
            url = try DFTProjectArtifactResolver(rootURL: rootURL).resolve(path)
        } catch {
            throw DFTLogicBISTCellMappingError.invalidPath(path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw DFTLogicBISTCellMappingError.readFailed(error.localizedDescription)
        }
        guard UInt64(data.count) == mapping.artifact.byteCount,
              try SHA256ContentDigester().digest(data: data) == mapping.artifact.digest else {
            throw DFTLogicBISTCellMappingError.identityMismatch(path)
        }
        do {
            return try JSONDecoder().decode(
                DFTLogicBISTCellMappingManifest.self,
                from: data
            )
        } catch {
            throw DFTLogicBISTCellMappingError.decodeFailed(error.localizedDescription)
        }
    }
}
