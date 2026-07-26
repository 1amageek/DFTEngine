import CircuiteFoundation
import Foundation

public enum DFTCellLibraryManifestCodec {
    public static func encode(_ manifest: DFTCellLibraryManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    public static func decode(_ data: Data) throws -> DFTCellLibraryManifest {
        try JSONDecoder().decode(DFTCellLibraryManifest.self, from: data)
    }

    public static func digest(_ manifest: DFTCellLibraryManifest) throws -> String {
        try SHA256ContentDigester().digest(data: encode(manifest)).hexadecimalValue
    }

    public static func validate(_ manifest: DFTCellLibraryManifest) throws {
        guard manifest.schemaVersion == DFTCellLibraryManifest.currentSchemaVersion else {
            throw DFTCellLibraryError.invalidManifest("unsupported schema version \(manifest.schemaVersion)")
        }
        guard !manifest.processID.isEmpty, !manifest.version.isEmpty else {
            throw DFTCellLibraryError.invalidManifest("process ID and version are required")
        }
        guard manifest.pdkDigest.count == 64,
              manifest.pdkDigest.allSatisfy(\.isHexDigit) else {
            throw DFTCellLibraryError.invalidManifest("PDK digest must be a SHA-256 value")
        }
        guard !manifest.bindings.isEmpty else {
            throw DFTCellLibraryError.invalidManifest("at least one sequential-cell binding is required")
        }
        let bindingIDs = manifest.bindings.map(\.bindingID)
        let functionalTypes = manifest.bindings.map(\.functionalCellType)
        guard Set(bindingIDs).count == bindingIDs.count,
              bindingIDs.allSatisfy({ !$0.isEmpty }) else {
            throw DFTCellLibraryError.invalidManifest("binding IDs must be non-empty and unique")
        }
        guard Set(functionalTypes).count == functionalTypes.count else {
            throw DFTCellLibraryError.invalidManifest("functional cell types must be unique")
        }
        for binding in manifest.bindings {
            guard !binding.functionalCellType.isEmpty,
                  !binding.scanCellType.isEmpty,
                  !binding.dataPinName.isEmpty,
                  !binding.outputPinName.isEmpty,
                  !binding.clockPinNames.isEmpty,
                  !binding.scanInPinName.isEmpty,
                  !binding.scanEnablePinName.isEmpty else {
                throw DFTCellLibraryError.invalidManifest(
                    "binding \(binding.bindingID) has an incomplete pin contract"
                )
            }
        }
        if let mapping = manifest.scanCompressionMapping {
            let cellTypes = [
                mapping.decompressorCellType,
                mapping.compactorCellType,
            ]
            let pinLists = [
                mapping.decompressorInputPinNames,
                mapping.decompressorOutputPinNames,
                mapping.compactorInputPinNames,
                mapping.compactorOutputPinNames,
            ]
            guard cellTypes.allSatisfy({
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }),
            pinLists.allSatisfy({
                !$0.isEmpty
                    && $0.allSatisfy {
                        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    && Set($0).count == $0.count
            }),
            Set(
                mapping.decompressorInputPinNames
                    + mapping.decompressorOutputPinNames
            ).count == mapping.decompressorInputPinNames.count
                + mapping.decompressorOutputPinNames.count,
            Set(
                mapping.compactorInputPinNames
                    + mapping.compactorOutputPinNames
            ).count == mapping.compactorInputPinNames.count
                + mapping.compactorOutputPinNames.count else {
                throw DFTCellLibraryError.invalidManifest(
                    "scan-compression cell and pin mappings must be non-empty and unambiguous"
                )
            }
        }
        guard manifest.evidenceProvenance.processID == nil
                || manifest.evidenceProvenance.processID == manifest.processID else {
            throw DFTCellLibraryError.invalidManifest(
                "evidence provenance process ID does not match the manifest process ID"
            )
        }
    }
}
