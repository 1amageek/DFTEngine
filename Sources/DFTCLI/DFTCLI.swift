import ATPGEngine
import BISTEngine
import DFTCore
import DFTEngine
import Darwin
import Foundation
import ScanInsertion

@main
enum DFTCLI {
    static func main() async {
        do {
            let exitCode = try await run(arguments: Array(CommandLine.arguments.dropFirst()))
            Darwin.exit(Int32(exitCode))
        } catch {
            writeError(error.localizedDescription)
            Darwin.exit(1)
        }
    }

    private static func run(arguments: [String]) async throws -> Int {
        guard let command = arguments.first else {
            writeOutput(usage)
            return 0
        }
        switch command {
        case "--help", "-h", "help":
            writeOutput(usage)
            return 0
        case "capabilities":
            guard arguments.dropFirst().isEmpty else {
                throw CLIError.unexpectedArguments(Array(arguments.dropFirst()))
            }
            let data = try DFTArtifactJSONEncoder().encode(capabilityReports())
            writeOutput(String(decoding: data, as: UTF8.self))
            return 0
        case "execute":
            return try await execute(arguments: Array(arguments.dropFirst()))
        default:
            throw CLIError.unknownCommand(command)
        }
    }

    private static func execute(arguments: [String]) async throws -> Int {
        try validateOptions(
            arguments,
            allowed: ["--request", "--output-dir", "--result"]
        )
        let requestPath = try requiredOption("--request", in: arguments)
        let outputDirectory = try requiredOption("--output-dir", in: arguments)
        let resultPath = option("--result", in: arguments)
        let requestURL = URL(fileURLWithPath: requestPath)
        let requestData: Data
        do {
            requestData = try Data(contentsOf: requestURL)
        } catch {
            throw CLIError.inputReadFailed(requestPath, error.localizedDescription)
        }
        let request: DFTRequest
        do {
            request = try JSONDecoder().decode(DFTRequest.self, from: requestData)
        } catch {
            throw CLIError.requestDecodeFailed(error.localizedDescription)
        }
        let projectRoot = URL(fileURLWithPath: outputDirectory)
        let store = FileSystemDFTArtifactStore(rootURL: projectRoot)
        let result = try await DefaultDFTEngine(
            artifactStore: store,
            designLoader: FileSystemDFTDesignLoader(rootURL: projectRoot),
            cellLibraryLoader: FileSystemDFTCellLibraryLoader(rootURL: projectRoot)
        ).execute(request)
        let data = try DFTArtifactJSONEncoder().encode(result)
        if let resultPath {
            do {
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: resultPath).deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: URL(fileURLWithPath: resultPath), options: .atomic)
            } catch {
                throw CLIError.resultWriteFailed(resultPath, error.localizedDescription)
            }
        } else {
            writeOutput(String(decoding: data, as: UTF8.self))
        }
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

    private static func capabilityReports() -> [DFTCapabilityReport] {
        let store = InMemoryDFTArtifactStore()
        return [
            DeterministicScanInsertionEngine(artifactStore: store).capabilityReport,
            DeterministicATPGEngine(artifactStore: store).capabilityReport,
            DeterministicBISTEngine(artifactStore: store).capabilityReport,
            DefaultDFTEngine(artifactStore: store).capabilityReport
        ]
    }

    private static func requiredOption(_ name: String, in arguments: [String]) throws -> String {
        guard let value = option(name, in: arguments), !value.isEmpty else {
            throw CLIError.optionMissing(name)
        }
        return value
    }

    private static func option(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func validateOptions(
        _ arguments: [String],
        allowed: Set<String>
    ) throws {
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard allowed.contains(argument) else {
                throw CLIError.unknownOption(argument)
            }
            guard seen.insert(argument).inserted else {
                throw CLIError.duplicateOption(argument)
            }
            guard index + 1 < arguments.count,
                  !arguments[index + 1].hasPrefix("--") else {
                throw CLIError.optionValueMissing(argument)
            }
            index += 2
        }
    }

    private static func writeOutput(_ value: String) {
        let data = Data((value + "\n").utf8)
        FileHandle.standardOutput.write(data)
    }

    private static func writeError(_ value: String) {
        let data = Data(("dft-engine: " + value + "\n").utf8)
        FileHandle.standardError.write(data)
    }

    private static let usage = """
    dft-engine — deterministic DFT contract runner

    Commands:
      dft-engine capabilities
      dft-engine execute --request <request.json> --output-dir <project-root> [--result <result.json>]

    The execute command emits a complete DFT result. Blocked executions use exit code 2.
    """
}

private enum CLIError: Error, LocalizedError {
    case unknownCommand(String)
    case unknownOption(String)
    case duplicateOption(String)
    case optionValueMissing(String)
    case unexpectedArguments([String])
    case optionMissing(String)
    case inputReadFailed(String, String)
    case requestDecodeFailed(String)
    case resultWriteFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .unknownCommand(let command):
            return "Unknown command '\(command)'. Use --help for usage."
        case .unknownOption(let option):
            return "Unknown option '\(option)'. Use --help for usage."
        case .duplicateOption(let option):
            return "Option '\(option)' must be specified at most once."
        case .optionValueMissing(let option):
            return "Option '\(option)' requires a value."
        case .unexpectedArguments(let arguments):
            return "Unexpected arguments: \(arguments.joined(separator: " "))."
        case .optionMissing(let option):
            return "Required option \(option) is missing."
        case .inputReadFailed(let path, let message):
            return "Could not read request \(path): \(message)."
        case .requestDecodeFailed(let message):
            return "Could not decode DFT request: \(message)."
        case .resultWriteFailed(let path, let message):
            return "Could not write result \(path): \(message)."
        }
    }
}
