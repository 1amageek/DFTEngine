import DFTCore
import Foundation
import SignoffToolSupport

public struct ProcessDFTExternalToolRunner: DFTExternalToolOutputProviding {
    public let descriptor: DFTExternalToolDescriptor
    public let executableURL: URL
    public let arguments: [String]
    public let workingDirectory: URL?
    public let environment: [String: String]?
    public let requestArgumentPlaceholder: String
    public let timeoutSeconds: Double
    public let terminationGraceSeconds: Double

    public init(
        descriptor: DFTExternalToolDescriptor,
        executableURL: URL,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        requestArgumentPlaceholder: String = "{request}",
        timeoutSeconds: Double = 300,
        terminationGraceSeconds: Double = 2
    ) {
        self.descriptor = descriptor
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.requestArgumentPlaceholder = requestArgumentPlaceholder
        self.timeoutSeconds = timeoutSeconds
        self.terminationGraceSeconds = terminationGraceSeconds
    }

    public func run(requestData: Data) async throws -> Data {
        try await runWithOutput(requestData: requestData).standardOutput
    }

    public func runWithOutput(requestData: Data) async throws -> DFTExternalToolOutput {
        let requestURL = FileManager.default.temporaryDirectory
            .appending(path: "dft-external-request-\(UUID().uuidString).json")
        do {
            try requestData.write(to: requestURL, options: .atomic)
        } catch {
            throw DFTExternalToolError.requestFileWriteFailed(error.localizedDescription)
        }

        do {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments.map { argument in
                argument == requestArgumentPlaceholder ? requestURL.path : argument
            }
            if !arguments.contains(requestArgumentPlaceholder) {
                process.arguments?.append(requestURL.path)
            }
            process.currentDirectoryURL = workingDirectory
            process.environment = environment
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            let result = try await TimedProcessRunner(
                timeoutSeconds: timeoutSeconds,
                terminationGraceSeconds: terminationGraceSeconds
            ).run(process: process)
            guard result.exitCode == 0 else {
                throw DFTExternalToolError.processFailed(
                    executablePath: executableURL.path,
                    exitCode: result.exitCode,
                    standardError: result.standardError
                )
            }
            let data = Data(result.standardOutput.utf8)
            do {
                try FileManager.default.removeItem(at: requestURL)
            } catch {
                throw DFTExternalToolError.requestFileCleanupFailed(error.localizedDescription)
            }
            return DFTExternalToolOutput(
                standardOutput: data,
                standardError: Data(result.standardError.utf8),
                exitCode: result.exitCode
            )
        } catch {
            do {
                try FileManager.default.removeItem(at: requestURL)
            } catch {
                throw DFTExternalToolError.requestFileCleanupFailed(error.localizedDescription)
            }
            throw error
        }
    }
}
