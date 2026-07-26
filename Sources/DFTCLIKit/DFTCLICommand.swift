import ATPGEngine
import BISTEngine
import CircuiteFoundation
import DFTCore
import DFTEngine
import DFTExternalTools
import Foundation
import ScanInsertion

public struct DFTCLICommand: Sendable {
    private let outputWriter: any DFTCLIOutputWriting

    public init(
        outputWriter: any DFTCLIOutputWriting = StandardDFTCLIOutputWriter()
    ) {
        self.outputWriter = outputWriter
    }

    public func run(arguments: [String]) async throws -> Int {
        guard let command = arguments.first else {
            outputWriter.writeOutput(Self.usage)
            return 0
        }
        switch command {
        case "--help", "-h", "help":
            outputWriter.writeOutput(Self.usage)
            return 0
        case "capabilities":
            guard arguments.dropFirst().isEmpty else {
                throw DFTCLIError.unexpectedArguments(Array(arguments.dropFirst()))
            }
            let data = try DFTArtifactJSONEncoder().encode(capabilityReports())
            outputWriter.writeOutput(String(decoding: data, as: UTF8.self))
            return 0
        case "execute":
            return try await execute(arguments: Array(arguments.dropFirst()))
        case "import-openroad-scan":
            return try await importOpenROADScan(
                arguments: Array(arguments.dropFirst())
            )
        case "replay":
            return try await replay(arguments: Array(arguments.dropFirst()))
        default:
            throw DFTCLIError.unknownCommand(command)
        }
    }

    private func importOpenROADScan(arguments: [String]) async throws -> Int {
        try validateOptions(
            arguments,
            allowed: ["--request", "--output-dir", "--result"]
        )
        let requestPath = try requiredOption("--request", in: arguments)
        let outputDirectory = try requiredOption("--output-dir", in: arguments)
        let request: OpenROADDFTScanImportRequest = try decodeRequest(
            at: requestPath
        )
        let store = FileSystemDFTArtifactStore(
            rootURL: URL(fileURLWithPath: outputDirectory)
        )
        let result = try await OpenROADDFTScanImporter(
            artifactReader: store,
            artifactStore: store
        ).importScan(request)
        try writeResult(
            try DFTArtifactJSONEncoder().encode(result),
            to: option("--result", in: arguments)
        )
        return 0
    }

    private func execute(arguments: [String]) async throws -> Int {
        try validateOptions(
            arguments,
            allowed: ["--request", "--output-dir", "--result"]
        )
        let requestPath = try requiredOption("--request", in: arguments)
        let outputDirectory = try requiredOption("--output-dir", in: arguments)
        let request: DFTRequest = try decodeRequest(at: requestPath)
        let projectRoot = URL(fileURLWithPath: outputDirectory)
        let store = FileSystemDFTArtifactStore(rootURL: projectRoot)
        for artifact in request.executionInputArtifacts {
            let input = try await store.data(for: artifact)
            guard UInt64(input.count) == artifact.byteCount,
                  try SHA256ContentDigester().digest(data: input)
                    == artifact.digest else {
                throw DFTCLIError.inputIdentityMismatch(artifact.path)
            }
        }
        let result = try await DefaultDFTEngine(
            artifactStore: store,
            designLoader: FileSystemDFTDesignLoader(rootURL: projectRoot),
            cellLibraryLoader: FileSystemDFTCellLibraryLoader(rootURL: projectRoot),
            timingLibraryLoader: FileSystemDFTTimingLibraryLoader(rootURL: projectRoot),
            constraintLoader: FileSystemDFTConstraintLoader(rootURL: projectRoot),
            logicBISTCellMappingLoader: FileSystemDFTLogicBISTCellMappingLoader(
                rootURL: projectRoot
            )
        ).execute(request)
        try writeResult(
            try DFTArtifactJSONEncoder().encode(result),
            to: option("--result", in: arguments)
        )
        switch result.status {
        case .completed:
            return 0
        case .blocked:
            return 2
        case .cancelled:
            return 3
        case .failed:
            return 1
        }
    }

    private func replay(arguments: [String]) async throws -> Int {
        try validateOptions(
            arguments,
            allowed: [
                "--request",
                "--output-dir",
                "--compiler",
                "--compiler-descriptor",
                "--simulator",
                "--simulator-descriptor",
                "--timeout-seconds",
                "--termination-grace-seconds",
                "--result",
            ]
        )
        let requestPath = try requiredOption("--request", in: arguments)
        let outputDirectory = try requiredOption("--output-dir", in: arguments)
        let compilerPath = try requiredOption("--compiler", in: arguments)
        let simulatorPath = try requiredOption("--simulator", in: arguments)
        let compilerDescriptor: DFTExternalToolDescriptor = try decodeDescriptor(
            at: requiredOption("--compiler-descriptor", in: arguments),
            role: "compiler"
        )
        let simulatorDescriptor: DFTExternalToolDescriptor = try decodeDescriptor(
            at: requiredOption("--simulator-descriptor", in: arguments),
            role: "simulator"
        )
        let request: DFTScanPatternReplayRequest = try decodeRequest(
            at: requestPath
        )
        let projectRoot = URL(fileURLWithPath: outputDirectory)
        let store = FileSystemDFTArtifactStore(rootURL: projectRoot)
        let result = try await IcarusDFTScanPatternReplayProvider(
            compilerDescriptor: compilerDescriptor,
            compilerURL: URL(fileURLWithPath: compilerPath),
            simulatorDescriptor: simulatorDescriptor,
            simulatorURL: URL(fileURLWithPath: simulatorPath),
            artifactReader: store,
            artifactStore: store,
            timeoutSeconds: try numericOption(
                "--timeout-seconds",
                in: arguments,
                default: 300
            ),
            terminationGraceSeconds: try numericOption(
                "--termination-grace-seconds",
                in: arguments,
                default: 2
            )
        ).replay(request)
        try writeResult(
            try DFTArtifactJSONEncoder().encode(result),
            to: option("--result", in: arguments)
        )
        return 0
    }

    private func capabilityReports() -> [DFTCapabilityReport] {
        let store = InMemoryDFTArtifactStore()
        return [
            DeterministicScanInsertionEngine(artifactStore: store).capabilityReport,
            DeterministicATPGEngine(artifactStore: store).capabilityReport,
            DeterministicBISTEngine(artifactStore: store).capabilityReport,
            DefaultDFTEngine(artifactStore: store).capabilityReport,
        ]
    }

    private func decodeRequest<Value: Decodable>(at path: String) throws -> Value {
        let data = try readInput(at: path)
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw DFTCLIError.requestDecodeFailed(error.localizedDescription)
        }
    }

    private func decodeDescriptor(
        at path: String,
        role: String
    ) throws -> DFTExternalToolDescriptor {
        let data = try readInput(at: path)
        do {
            return try JSONDecoder().decode(
                DFTExternalToolDescriptor.self,
                from: data
            )
        } catch {
            throw DFTCLIError.descriptorDecodeFailed(
                role: role,
                message: error.localizedDescription
            )
        }
    }

    private func readInput(at path: String) throws -> Data {
        do {
            return try Data(
                contentsOf: URL(fileURLWithPath: path),
                options: .mappedIfSafe
            )
        } catch {
            throw DFTCLIError.inputReadFailed(path, error.localizedDescription)
        }
    }

    private func writeResult(_ data: Data, to path: String?) throws {
        guard let path else {
            outputWriter.writeOutput(String(decoding: data, as: UTF8.self))
            return
        }
        do {
            let resultURL = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: resultURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: resultURL, options: .atomic)
        } catch {
            throw DFTCLIError.resultWriteFailed(path, error.localizedDescription)
        }
    }

    private func requiredOption(
        _ name: String,
        in arguments: [String]
    ) throws -> String {
        guard let value = option(name, in: arguments), !value.isEmpty else {
            throw DFTCLIError.optionMissing(name)
        }
        return value
    }

    private func option(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name),
              index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private func numericOption(
        _ name: String,
        in arguments: [String],
        default defaultValue: Double
    ) throws -> Double {
        guard let value = option(name, in: arguments) else {
            return defaultValue
        }
        guard let result = Double(value), result.isFinite else {
            throw DFTCLIError.invalidNumericOption(name: name, value: value)
        }
        return result
    }

    private func validateOptions(
        _ arguments: [String],
        allowed: Set<String>
    ) throws {
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard allowed.contains(argument) else {
                throw DFTCLIError.unknownOption(argument)
            }
            guard seen.insert(argument).inserted else {
                throw DFTCLIError.duplicateOption(argument)
            }
            guard index + 1 < arguments.count,
                  !arguments[index + 1].hasPrefix("--") else {
                throw DFTCLIError.optionValueMissing(argument)
            }
            index += 2
        }
    }

    private static let usage = """
    dft-engine — deterministic DFT contract runner

    Commands:
      dft-engine capabilities
      dft-engine execute --request <request.json> --output-dir <project-root> [--result <result.json>]
      dft-engine import-openroad-scan --request <request.json>
        --output-dir <project-root> [--result <result.json>]
      dft-engine replay --request <request.json> --output-dir <project-root>
        --compiler <iverilog> --compiler-descriptor <descriptor.json>
        --simulator <vvp> --simulator-descriptor <descriptor.json>
        [--timeout-seconds <seconds>] [--termination-grace-seconds <seconds>]
        [--result <result.json>]

    Execute emits a DFT result and uses exit code 2 for blocked execution.
    Replay verifies retained input and executable identities before execution.
    """
}
