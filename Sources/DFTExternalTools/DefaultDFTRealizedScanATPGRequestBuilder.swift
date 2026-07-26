import CircuiteFoundation
import DFTCore
import Foundation

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
            scanImplementation: importResult.scanImplementation,
            operation: .atpg,
            scanArchitecture: architecture,
            atpgConfiguration: configuration.atpg
        )
    }
}
