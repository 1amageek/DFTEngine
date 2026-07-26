import CircuiteFoundation
import DFTCore
import Foundation
import PDKCore

public struct DefaultDFTRealizedScanATPGRequestBuilder:
    DFTRealizedScanATPGRequestBuilding
{
    private let artifactReader: any DFTArtifactReading

    public init(artifactReader: any DFTArtifactReading) {
        self.artifactReader = artifactReader
    }

    public func build(
        importResult: OpenROADDFTScanImportResult,
        configuration: DFTRealizedScanATPGRequestConfiguration
    ) async throws -> DFTRequest {
        guard !configuration.runID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw DFTRealizedScanATPGRequestBuilderError.emptyRunID
        }
        guard configuration.atpg.faultSource == .gateLevel else {
            throw DFTRealizedScanATPGRequestBuilderError
                .gateLevelFaultSourceRequired
        }
        try configuration.pdk.validate()
        guard importResult.processID == configuration.pdk.processID,
              importResult.pdkDigest == configuration.pdk.digest else {
            throw DFTRealizedScanATPGRequestBuilderError.processMismatch
        }
        try await validateCellLibrary(
            configuration.cellLibrary,
            importResult: importResult,
            pdk: configuration.pdk
        )

        let reference = importResult.scanImplementation.artifact
        let data = try await artifactReader.data(for: reference)
        guard UInt64(data.count) == reference.byteCount,
              try SHA256ContentDigester().digest(data: data)
                == reference.digest else {
            throw DFTRealizedScanATPGRequestBuilderError
                .inputIdentityMismatch(reference.path)
        }
        let implementation: DFTScanImplementation
        do {
            implementation = try JSONDecoder().decode(
                DFTScanImplementation.self,
                from: data
            )
        } catch {
            throw DFTRealizedScanATPGRequestBuilderError
                .scanImplementationDecodeFailed(error.localizedDescription)
        }
        let issues = DFTScanImplementationValidator()
            .validationIssues(in: implementation)
        guard issues.isEmpty else {
            throw DFTRealizedScanATPGRequestBuilderError
                .scanImplementationInvalid(issues.map(\.code))
        }
        guard implementation.transformedDesignDigest
                == importResult.transformedDesign.designDigest,
              importResult.scanImplementation.transformedDesignDigest
                == importResult.transformedDesign.designDigest else {
            throw DFTRealizedScanATPGRequestBuilderError
                .transformedDesignMismatch
        }

        let clockIDs = configuration.clocks.map(\.id)
        guard !clockIDs.contains(where: { $0.isEmpty }),
              Set(clockIDs).count == clockIDs.count else {
            throw DFTRealizedScanATPGRequestBuilderError.clockIDsInvalid
        }
        let chainsByDomain = Dictionary(
            grouping: implementation.chains,
            by: \.domainID
        )
        guard Set(chainsByDomain.keys)
                == Set(configuration.domainClockIDs.keys) else {
            throw DFTRealizedScanATPGRequestBuilderError
                .domainClockMappingMismatch
        }
        let knownClockIDs = Set(clockIDs)
        let domains = try chainsByDomain.keys.sorted().map { domainID in
            guard let clockID = configuration.domainClockIDs[domainID],
                  knownClockIDs.contains(clockID) else {
                throw DFTRealizedScanATPGRequestBuilderError.unknownClockID(
                    domainID: domainID,
                    clockID: configuration.domainClockIDs[domainID] ?? ""
                )
            }
            let chains = chainsByDomain[domainID, default: []]
            let lengths = chains.map(\.elements.count)
            return DFTScanDomain(
                id: domainID,
                clockID: clockID,
                chainCount: chains.count,
                estimatedElementCount: lengths.reduce(0, +),
                maximumChainLength: lengths.max()
            )
        }
        let architecture = DFTScanArchitecture(
            name: implementation.architectureName,
            clocks: configuration.clocks,
            domains: domains,
            scanEnableSignal: implementation.scanEnableSignal,
            testModeSignal: implementation.testModeSignal
        )
        return DFTRequest(
            runID: configuration.runID,
            inputs: [
                importResult.transformedDesign.artifact,
                importResult.scanImplementation.artifact,
            ],
            design: importResult.transformedDesign,
            constraints: configuration.constraints,
            pdk: configuration.pdk,
            cellLibrary: configuration.cellLibrary,
            scanImplementation: importResult.scanImplementation,
            operation: .atpg,
            scanArchitecture: architecture,
            atpgConfiguration: configuration.atpg
        )
    }

    private func validateCellLibrary(
        _ reference: DFTCellLibraryReference,
        importResult: OpenROADDFTScanImportResult,
        pdk: PDKReference
    ) async throws {
        guard reference.processID == pdk.processID,
              reference.version == pdk.version,
              importResult.inputs.contains(reference.artifact),
              reference.timingLibraryArtifact != nil else {
            throw DFTRealizedScanATPGRequestBuilderError.cellLibraryMismatch(
                "the exact imported manifest and one timing library are required"
            )
        }
        let data = try await artifactReader.data(for: reference.artifact)
        guard UInt64(data.count) == reference.artifact.byteCount,
              try SHA256ContentDigester().digest(data: data)
                == reference.artifact.digest else {
            throw DFTRealizedScanATPGRequestBuilderError
                .inputIdentityMismatch(reference.artifact.path)
        }
        let manifest: DFTCellLibraryManifest
        do {
            manifest = try DFTCellLibraryManifestCodec.decode(data)
            try DFTCellLibraryManifestCodec.validate(manifest)
        } catch {
            throw DFTRealizedScanATPGRequestBuilderError.cellLibraryMismatch(
                error.localizedDescription
            )
        }
        guard manifest.processID == pdk.processID,
              manifest.version == pdk.version,
              manifest.pdkDigest == pdk.digest,
              try DFTCellLibraryManifestCodec.digest(manifest)
                == reference.manifestDigest else {
            throw DFTRealizedScanATPGRequestBuilderError.cellLibraryMismatch(
                "manifest process, version, PDK, or canonical digest differs"
            )
        }
    }
}
