import Foundation

enum DFTCLIError: Error, LocalizedError {
    case unknownCommand(String)
    case unknownOption(String)
    case duplicateOption(String)
    case optionValueMissing(String)
    case unexpectedArguments([String])
    case optionMissing(String)
    case inputReadFailed(String, String)
    case inputIdentityMismatch(String)
    case requestDecodeFailed(String)
    case descriptorDecodeFailed(role: String, message: String)
    case invalidNumericOption(name: String, value: String)
    case resultWriteFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .unknownCommand(let command):
            return "Unknown command '\(command)'. Use --help for usage."
        case .unknownOption(let option):
            return "Unknown option \(option). Use --help for usage."
        case .duplicateOption(let option):
            return "Option \(option) must be specified at most once."
        case .optionValueMissing(let option):
            return "Option \(option) requires a value."
        case .unexpectedArguments(let arguments):
            return "Unexpected arguments: \(arguments.joined(separator: " "))."
        case .optionMissing(let option):
            return "Required option \(option) is missing."
        case .inputReadFailed(let path, let message):
            return "Could not read input \(path): \(message)."
        case .inputIdentityMismatch(let path):
            return "Input artifact identity does not match retained content at \(path)."
        case .requestDecodeFailed(let message):
            return "Could not decode DFT request: \(message)."
        case .descriptorDecodeFailed(let role, let message):
            return "Could not decode \(role) descriptor: \(message)."
        case .invalidNumericOption(let name, let value):
            return "Option \(name) requires a finite numeric value, not '\(value)'."
        case .resultWriteFailed(let path, let message):
            return "Could not write result \(path): \(message)."
        }
    }
}
