import CircuiteFoundation
import DFTCore
import DFTPatternExchange
import Foundation
import SignoffToolSupport

public struct IcarusDFTScanPatternReplayProvider: DFTScanPatternReplayProviding {
    public let compilerDescriptor: DFTExternalToolDescriptor
    public let compilerURL: URL
    public let simulatorDescriptor: DFTExternalToolDescriptor
    public let simulatorURL: URL
    public let artifactReader: any DFTArtifactReading
    public let artifactStore: any DFTArtifactStoring
    public let timeoutSeconds: Double
    public let terminationGraceSeconds: Double

    public init(
        compilerDescriptor: DFTExternalToolDescriptor,
        compilerURL: URL,
        simulatorDescriptor: DFTExternalToolDescriptor,
        simulatorURL: URL,
        artifactReader: any DFTArtifactReading,
        artifactStore: any DFTArtifactStoring,
        timeoutSeconds: Double = 300,
        terminationGraceSeconds: Double = 2
    ) {
        self.compilerDescriptor = compilerDescriptor
        self.compilerURL = compilerURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        self.simulatorDescriptor = simulatorDescriptor
        self.simulatorURL = simulatorURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        self.artifactReader = artifactReader
        self.artifactStore = artifactStore
        self.timeoutSeconds = timeoutSeconds
        self.terminationGraceSeconds = terminationGraceSeconds
    }

    public func replay(
        _ request: DFTScanPatternReplayRequest
    ) async throws -> DFTScanPatternReplayResult {
        try validate(request)
        let inputs = [
            request.patternArtifact,
            request.scanNetlistArtifact,
            request.scanImplementation.artifact,
            request.faultUniverseArtifact,
        ] + request.cellModelArtifacts
        let inputData = try await load(inputs)
        let patternData = inputData[0]
        let scanNetlistData = inputData[1]
        let scanImplementationData = inputData[2]
        let faultUniverseData = inputData[3]
        let cellModelData = Array(inputData.dropFirst(4))
        let program: DFTPatternExchangeProgram
        do {
            program = try STILPatternCodec().decode(patternData)
        } catch {
            throw DFTScanPatternReplayError.patternDecodeFailed(
                error.localizedDescription
            )
        }
        let scanImplementation: DFTScanImplementation = try decodeJSON(
            scanImplementationData,
            name: "scan implementation"
        )
        let faultUniverse: DFTFaultUniverse = try decodeJSON(
            faultUniverseData,
            name: "fault universe"
        )
        try validate(
            scanImplementation: scanImplementation,
            reference: request.scanImplementation,
            program: program
        )
        let faults = try replayFaults(
            faultUniverse: faultUniverse,
            selectedFaultIDs: request.faultIDs,
            topModule: request.topModule
        )
        let harness: Data
        do {
            harness = try VerilogDFTReplayHarnessBuilder().build(
                program: program,
                topModule: request.topModule,
                faults: faults
            )
        } catch let error as DFTScanPatternReplayError {
            throw error
        } catch {
            throw DFTScanPatternReplayError.harnessGenerationFailed(
                error.localizedDescription
            )
        }

        let workspace = FileManager.default.temporaryDirectory
            .appending(
                path: "dft-icarus-replay-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        do {
            try FileManager.default.createDirectory(
                at: workspace,
                withIntermediateDirectories: false
            )
        } catch {
            throw DFTScanPatternReplayError.temporaryWorkspaceFailed(
                error.localizedDescription
            )
        }

        do {
            let result = try await execute(
                request: request,
                inputs: inputs,
                scanImplementation: scanImplementation,
                faultUniverse: faultUniverse,
                faults: faults,
                scanNetlistData: scanNetlistData,
                cellModelData: cellModelData,
                harness: harness,
                workspace: workspace
            )
            try removeWorkspace(workspace)
            return result
        } catch {
            do {
                try removeWorkspace(workspace)
            } catch let cleanupError as DFTScanPatternReplayError {
                throw cleanupError
            }
            throw error
        }
    }

    private func execute(
        request: DFTScanPatternReplayRequest,
        inputs: [ArtifactReference],
        scanImplementation: DFTScanImplementation,
        faultUniverse: DFTFaultUniverse,
        faults: [DFTScanPatternReplayFault],
        scanNetlistData: Data,
        cellModelData: [Data],
        harness: Data,
        workspace: URL
    ) async throws -> DFTScanPatternReplayResult {
        let netlistURL = workspace.appending(path: "scan-netlist.v")
        let harnessURL = workspace.appending(path: "dft-replay-harness.sv")
        let imageURL = workspace.appending(path: "dft-replay.vvp")
        do {
            try scanNetlistData.write(to: netlistURL, options: .atomic)
            try harness.write(to: harnessURL, options: .atomic)
        } catch {
            throw DFTScanPatternReplayError.temporaryWorkspaceFailed(
                error.localizedDescription
            )
        }
        var modelURLs: [URL] = []
        for (index, data) in cellModelData.enumerated() {
            let modelURL = workspace.appending(path: "cell-model-\(index).v")
            do {
                try data.write(to: modelURL, options: .atomic)
            } catch {
                throw DFTScanPatternReplayError.temporaryWorkspaceFailed(
                    error.localizedDescription
                )
            }
            modelURLs.append(modelURL)
        }

        var compilerArguments = [
            "-g2012",
        ]
        for define in request.preprocessorDefines {
            compilerArguments.append("-D\(define)")
        }
        compilerArguments += [
            "-s",
            "dft_replay_harness",
            "-o",
            imageURL.path,
        ]
        compilerArguments += modelURLs.map(\.path)
        compilerArguments += [
            netlistURL.path,
            harnessURL.path,
        ]

        let compilerInvocation = try await run(
            descriptor: compilerDescriptor,
            executableURL: compilerURL,
            arguments: compilerArguments,
            workspace: workspace
        )
        guard compilerInvocation.exitCode == 0 else {
            throw DFTScanPatternReplayError.processFailed(
                implementationID: compilerDescriptor.implementationID,
                exitCode: compilerInvocation.exitCode,
                standardError: compilerInvocation.standardError
            )
        }
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw DFTScanPatternReplayError.replayOutputInvalid(
                "Icarus compiler did not create the simulation image"
            )
        }

        let goldenInvocation = try await run(
            descriptor: simulatorDescriptor,
            executableURL: simulatorURL,
            arguments: [imageURL.path],
            workspace: workspace
        )
        guard goldenInvocation.exitCode == 0,
              markerCount(
                  "DFT_REPLAY_GOLDEN_COMPLETE",
                  in: goldenInvocation.standardOutput
              ) == 1,
              !goldenInvocation.standardOutput.contains(
                  "DFT_REPLAY_GOLDEN_MISMATCH"
              ),
              !goldenInvocation.standardOutput.contains(
                  "DFT_REPLAY_UNKNOWN_COMPARE"
              ),
              !goldenInvocation.standardOutput.contains(
                  "DFT_REPLAY_RESULT"
              ) else {
            throw DFTScanPatternReplayError.goldenReplayMismatch(
                goldenInvocation.standardOutput
                    + goldenInvocation.standardError
            )
        }

        var faultInvocations: [DFTReplayInvocationEvidence] = []
        var observations: [DFTScanPatternReplayObservation] = []
        for (index, fault) in faults.enumerated() {
            let invocation = try await run(
                descriptor: simulatorDescriptor,
                executableURL: simulatorURL,
                arguments: [
                    imageURL.path,
                    "+DFT_FAULT_INDEX=\(index)",
                ],
                workspace: workspace
            )
            guard invocation.exitCode == 0 else {
                throw DFTScanPatternReplayError.processFailed(
                    implementationID: simulatorDescriptor.implementationID,
                    exitCode: invocation.exitCode,
                    standardError: invocation.standardError
                )
            }
            let mismatchCount = try parseMismatchCount(
                invocation.standardOutput,
                expectedIndex: index
            )
            observations.append(
                DFTScanPatternReplayObservation(
                    faultID: fault.faultID,
                    detected: mismatchCount > 0,
                    mismatchCount: mismatchCount
                )
            )
            faultInvocations.append(invocation)
        }

        let scanImplementationDigest: String
        let faultUniverseDigest: String
        do {
            scanImplementationDigest = try DFTDeterministicHasher()
                .digest(scanImplementation)
            faultUniverseDigest = try DFTDeterministicHasher()
                .digest(faultUniverse)
        } catch {
            throw DFTScanPatternReplayError.replayOutputInvalid(
                "semantic input digest generation failed: \(error.localizedDescription)"
            )
        }
        let imageData: Data
        do {
            imageData = try Data(contentsOf: imageURL, options: .mappedIfSafe)
        } catch {
            throw DFTScanPatternReplayError.replayOutputInvalid(
                "simulation image could not be retained: \(error.localizedDescription)"
            )
        }
        let evidence = DFTScanPatternReplayEvidence(
            compiler: compilerDescriptor,
            simulator: simulatorDescriptor,
            scanImplementationDigest: scanImplementationDigest,
            faultUniverseDigest: faultUniverseDigest,
            inputs: inputs,
            compilerInvocation: compilerInvocation,
            goldenInvocation: goldenInvocation,
            faultInvocations: faultInvocations,
            observations: observations
        )
        let evidenceData: Data
        do {
            evidenceData = try DFTArtifactJSONEncoder().encode(evidence)
        } catch {
            throw DFTScanPatternReplayError.artifactPersistenceFailed(
                error.localizedDescription
            )
        }
        let artifacts: [ArtifactReference]
        do {
            artifacts = try await artifactStore.storeBatch(
                [
                    DFTArtifactContent(
                        artifactID: "dft-icarus-replay-harness",
                        fileName: "icarus-replay-harness.sv",
                        kind: .testPattern,
                        format: .systemVerilog,
                        data: harness
                    ),
                    DFTArtifactContent(
                        artifactID: "dft-icarus-replay-image",
                        fileName: "icarus-replay.vvp",
                        kind: .testPattern,
                        format: .raw,
                        data: imageData
                    ),
                    DFTArtifactContent(
                        artifactID: "dft-icarus-replay-evidence",
                        fileName: "icarus-replay-evidence.json",
                        kind: .evidence,
                        format: .json,
                        data: evidenceData
                    ),
                ],
                runID: request.runID
            )
        } catch {
            throw DFTScanPatternReplayError.artifactPersistenceFailed(
                error.localizedDescription
            )
        }
        return DFTScanPatternReplayResult(
            runID: request.runID,
            compiler: compilerDescriptor,
            simulator: simulatorDescriptor,
            scanImplementationDigest: scanImplementationDigest,
            faultUniverseDigest: faultUniverseDigest,
            inputs: inputs,
            observations: observations,
            artifacts: artifacts
        )
    }

    private func validate(_ request: DFTScanPatternReplayRequest) throws {
        guard request.schemaVersion == DFTScanPatternReplayRequest.currentSchemaVersion else {
            throw DFTScanPatternReplayError.invalidRequest(
                "unsupported schema version \(request.schemaVersion)"
            )
        }
        guard !request.runID.isEmpty, !request.topModule.isEmpty else {
            throw DFTScanPatternReplayError.invalidRequest(
                "run ID and top module are required"
            )
        }
        guard isIdentifier(request.topModule) else {
            throw DFTScanPatternReplayError.invalidRequest(
                "top module must be an unescaped Verilog identifier"
            )
        }
        guard !request.cellModelArtifacts.isEmpty else {
            throw DFTScanPatternReplayError.invalidRequest(
                "at least one cell model artifact is required"
            )
        }
        guard !request.faultIDs.isEmpty else {
            throw DFTScanPatternReplayError.invalidRequest(
                "at least one explicit fault is required"
            )
        }
        guard timeoutSeconds.isFinite, timeoutSeconds > 0,
              terminationGraceSeconds.isFinite, terminationGraceSeconds >= 0 else {
            throw DFTScanPatternReplayError.invalidRequest(
                "process timeouts must be finite and non-negative"
            )
        }
        guard compilerDescriptor.implementationID
                != simulatorDescriptor.implementationID else {
            throw DFTScanPatternReplayError.invalidRequest(
                "compiler and simulator identities must be distinct"
            )
        }
        guard compilerURL != simulatorURL else {
            throw DFTScanPatternReplayError.invalidRequest(
                "compiler and simulator executables must be distinct"
            )
        }
        try validateDescriptor(compilerDescriptor)
        try validateDescriptor(simulatorDescriptor)
        try validateInputArtifacts(request)
        var defines: Set<String> = []
        for define in request.preprocessorDefines {
            guard isIdentifier(define),
                  defines.insert(define).inserted else {
                throw DFTScanPatternReplayError.invalidRequest(
                    "preprocessor defines must be unique identifiers"
                )
            }
        }
    }

    private func validateDescriptor(
        _ descriptor: DFTExternalToolDescriptor
    ) throws {
        guard !descriptor.engineID.isEmpty,
              !descriptor.implementationID.isEmpty,
              !descriptor.implementationVersion.isEmpty,
              descriptor.binaryDigest.range(
                  of: #"^[0-9a-f]{64}$"#,
                  options: .regularExpression
              ) != nil else {
            throw DFTScanPatternReplayError.invalidRequest(
                "tool descriptors require identities, versions, and SHA-256 binary digests"
            )
        }
    }

    private func validateInputArtifacts(
        _ request: DFTScanPatternReplayRequest
    ) throws {
        guard request.patternArtifact.locator.kind == .testPattern,
              request.patternArtifact.locator.format == .stil else {
            throw DFTScanPatternReplayError.invalidRequest(
                "pattern artifact must be a STIL test-pattern artifact"
            )
        }
        guard request.scanNetlistArtifact.locator.kind == .netlist,
              isVerilog(request.scanNetlistArtifact.locator.format) else {
            throw DFTScanPatternReplayError.invalidRequest(
                "scan netlist artifact must be a Verilog netlist artifact"
            )
        }
        guard request.scanImplementation.artifact.locator.kind == .report,
              request.scanImplementation.artifact.locator.format == .json else {
            throw DFTScanPatternReplayError.invalidRequest(
                "scan implementation artifact must be a JSON report artifact"
            )
        }
        guard request.faultUniverseArtifact.locator.kind == .input,
              request.faultUniverseArtifact.locator.format == .json else {
            throw DFTScanPatternReplayError.invalidRequest(
                "fault universe artifact must be a JSON input artifact"
            )
        }
        for artifact in request.cellModelArtifacts {
            guard artifact.locator.kind == .model,
                  isVerilog(artifact.locator.format) else {
                throw DFTScanPatternReplayError.invalidRequest(
                    "cell model artifacts must be Verilog model artifacts"
                )
            }
        }
        let artifacts = [
            request.patternArtifact,
            request.scanNetlistArtifact,
            request.scanImplementation.artifact,
            request.faultUniverseArtifact,
        ] + request.cellModelArtifacts
        guard Set(artifacts.map(\.id)).count == artifacts.count else {
            throw DFTScanPatternReplayError.invalidRequest(
                "input artifact identities must be unique"
            )
        }
        guard artifacts.allSatisfy({
            $0.digest.algorithm == .sha256 && $0.byteCount > 0
        }) else {
            throw DFTScanPatternReplayError.invalidRequest(
                "input artifacts require non-empty SHA-256-addressed content"
            )
        }
    }

    private func validate(
        scanImplementation: DFTScanImplementation,
        reference: DFTScanImplementationReference,
        program: DFTPatternExchangeProgram
    ) throws {
        let validationIssues = DFTScanImplementationValidator()
            .validationIssues(in: scanImplementation)
        guard validationIssues.isEmpty else {
            throw DFTScanPatternReplayError.invalidRequest(
                "scan implementation validation failed: "
                    + validationIssues.map(\.code).joined(separator: ", ")
            )
        }
        guard scanImplementation.transformedDesignDigest
                == reference.transformedDesignDigest else {
            throw DFTScanPatternReplayError.invalidRequest(
                "scan implementation reference has a different transformed design digest"
            )
        }
        let chainIDs = scanImplementation.chains.map(\.chainID)
        guard Set(chainIDs).count == chainIDs.count else {
            throw DFTScanPatternReplayError.invalidRequest(
                "realized scan chain identities must be unique"
            )
        }
        let inputs = Set(program.signals.filter {
            $0.direction == .input
        }.map(\.name))
        let outputs = Set(program.signals.filter {
            $0.direction == .output
        }.map(\.name))
        guard inputs.contains(scanImplementation.scanEnableSignal),
              inputs.contains(scanImplementation.testModeSignal),
              scanImplementation.chains.allSatisfy({
                  inputs.contains($0.scanInSignal)
                    && outputs.contains($0.scanOutSignal)
              }) else {
            throw DFTScanPatternReplayError.invalidRequest(
                "STIL signals do not match the retained scan implementation"
            )
        }
    }

    private func replayFaults(
        faultUniverse: DFTFaultUniverse,
        selectedFaultIDs: [String],
        topModule: String
    ) throws -> [DFTScanPatternReplayFault] {
        let issues = faultUniverse.validationIssues()
        guard issues.isEmpty else {
            throw DFTScanPatternReplayError.invalidRequest(
                "fault universe validation failed: "
                    + issues.map(\.code).joined(separator: ", ")
            )
        }
        guard Set(selectedFaultIDs).count == selectedFaultIDs.count,
              selectedFaultIDs.allSatisfy({ !$0.isEmpty }) else {
            throw DFTScanPatternReplayError.invalidRequest(
                "selected fault IDs must be non-empty and unique"
            )
        }
        let faultsByID = Dictionary(
            uniqueKeysWithValues: faultUniverse.faults.map {
                ($0.id, $0)
            }
        )
        let excluded = Set(faultUniverse.excludedFaultIDs)
        return try selectedFaultIDs.map { faultID in
            guard let fault = faultsByID[faultID],
                  !excluded.contains(faultID),
                  fault.family == .stuckAt,
                  let value = fault.stuckAtValue else {
                throw DFTScanPatternReplayError.invalidRequest(
                    "selected fault \(faultID) must be an active stuck-at fault"
                )
            }
            return DFTScanPatternReplayFault(
                faultID: fault.id,
                hierarchicalSignalPath:
                    try DFTFaultLocationProjector().dutRelativePath(
                        for: fault.location,
                        topModule: topModule
                    ),
                stuckAtValue: value == .one
            )
        }
    }

    private func decodeJSON<Value: Decodable>(
        _ data: Data,
        name: String
    ) throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw DFTScanPatternReplayError.inputDecodeFailed(
                name: name,
                message: error.localizedDescription
            )
        }
    }

    private func load(
        _ references: [ArtifactReference]
    ) async throws -> [Data] {
        var result: [Data] = []
        result.reserveCapacity(references.count)
        for reference in references {
            let data = try await artifactReader.data(for: reference)
            let digest = try SHA256ContentDigester().digest(data: data)
            guard digest == reference.digest,
                  UInt64(data.count) == reference.byteCount else {
                throw DFTScanPatternReplayError.artifactIntegrityMismatch(
                    path: reference.path
                )
            }
            result.append(data)
        }
        return result
    }

    private func run(
        descriptor: DFTExternalToolDescriptor,
        executableURL: URL,
        arguments: [String],
        workspace: URL
    ) async throws -> DFTReplayInvocationEvidence {
        let digestBefore = try executableDigest(executableURL)
        guard digestBefore.caseInsensitiveCompare(
            descriptor.binaryDigest
        ) == .orderedSame else {
            throw DFTScanPatternReplayError.executableIdentityMismatch(
                implementationID: descriptor.implementationID,
                expected: descriptor.binaryDigest,
                actual: digestBefore
            )
        }
        let result: TimedProcessResult
        do {
            result = try await TimedProcessRunner(
                timeoutSeconds: timeoutSeconds,
                terminationGraceSeconds: terminationGraceSeconds
            ).run(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectory: workspace
            )
        } catch {
            try verifyExecutableUnchanged(
                descriptor: descriptor,
                executableURL: executableURL,
                digestBefore: digestBefore
            )
            throw mapProcessError(error, descriptor: descriptor)
        }
        try verifyExecutableUnchanged(
            descriptor: descriptor,
            executableURL: executableURL,
            digestBefore: digestBefore
        )
        return DFTReplayInvocationEvidence(
            implementationID: descriptor.implementationID,
            arguments: arguments,
            exitCode: result.exitCode,
            standardOutput: result.standardOutput,
            standardError: result.standardError
        )
    }

    private func verifyExecutableUnchanged(
        descriptor: DFTExternalToolDescriptor,
        executableURL: URL,
        digestBefore: String
    ) throws {
        let digestAfter = try executableDigest(executableURL)
        guard digestAfter == digestBefore else {
            throw DFTScanPatternReplayError.executableIdentityMismatch(
                implementationID: descriptor.implementationID,
                expected: digestBefore,
                actual: digestAfter
            )
        }
    }

    private func mapProcessError(
        _ error: any Error,
        descriptor: DFTExternalToolDescriptor
    ) -> DFTScanPatternReplayError {
        guard let processError = error as? TimedProcessError else {
            return .processLaunchFailed(
                implementationID: descriptor.implementationID,
                message: error.localizedDescription
            )
        }
        switch processError {
        case .timedOut(_, let timeoutSeconds, _, _):
            return .processTimedOut(
                implementationID: descriptor.implementationID,
                timeoutSeconds: timeoutSeconds
            )
        case .cancelled:
            return .processCancelled(
                implementationID: descriptor.implementationID
            )
        case .launchFailed(_, let message),
             .invalidConfiguration(let message),
             .cancellationCheckFailed(_, let message, _, _):
            return .processLaunchFailed(
                implementationID: descriptor.implementationID,
                message: message
            )
        }
    }

    private func executableDigest(_ url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw DFTScanPatternReplayError.invalidRequest(
                "executable \(url.path) cannot be read: \(error.localizedDescription)"
            )
        }
        return try SHA256ContentDigester()
            .digest(data: data)
            .hexadecimalValue
    }

    private func parseMismatchCount(
        _ output: String,
        expectedIndex: Int
    ) throws -> Int {
        let pattern = #"DFT_REPLAY_RESULT index=([0-9]+) mismatches=([0-9]+)"#
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(output.startIndex..., in: output)
        let matches = expression.matches(
            in: output,
            range: range
        )
        guard matches.count == 1,
              !output.contains("DFT_REPLAY_GOLDEN_COMPLETE"),
              !output.contains("DFT_REPLAY_GOLDEN_MISMATCH"),
              !output.contains("DFT_REPLAY_UNKNOWN_COMPARE"),
              let match = matches.first,
              let indexRange = Range(match.range(at: 1), in: output),
              let mismatchRange = Range(match.range(at: 2), in: output),
              let actualIndex = Int(output[indexRange]),
              let mismatchCount = Int(output[mismatchRange]),
              actualIndex == expectedIndex else {
            throw DFTScanPatternReplayError.replayOutputInvalid(
                "missing or mismatched replay result marker for fault index \(expectedIndex)"
            )
        }
        return mismatchCount
    }

    private func markerCount(
        _ marker: String,
        in output: String
    ) -> Int {
        output.components(separatedBy: marker).count - 1
    }

    private func removeWorkspace(_ workspace: URL) throws {
        do {
            try FileManager.default.removeItem(at: workspace)
        } catch {
            throw DFTScanPatternReplayError.temporaryWorkspaceCleanupFailed(
                error.localizedDescription
            )
        }
    }

    private func isIdentifier(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z_][A-Za-z0-9_$]*$"#,
            options: .regularExpression
        ) != nil
    }

    private func isVerilog(_ format: ArtifactFormat) -> Bool {
        format == .verilog || format == .systemVerilog
    }
}

private struct DFTScanPatternReplayEvidence: Sendable, Hashable, Codable {
    let compiler: DFTExternalToolDescriptor
    let simulator: DFTExternalToolDescriptor
    let scanImplementationDigest: String
    let faultUniverseDigest: String
    let inputs: [ArtifactReference]
    let compilerInvocation: DFTReplayInvocationEvidence
    let goldenInvocation: DFTReplayInvocationEvidence
    let faultInvocations: [DFTReplayInvocationEvidence]
    let observations: [DFTScanPatternReplayObservation]
}

private struct DFTReplayInvocationEvidence: Sendable, Hashable, Codable {
    let implementationID: String
    let arguments: [String]
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}
