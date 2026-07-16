import Foundation

public enum DFTDiagnosticSeverity: String, Sendable, Hashable, Codable {
    case info
    case warning
    case error
}

/// Domain diagnostic retained while the DFT payload is evaluated.
public struct DFTDiagnostic: Sendable, Hashable, Codable {
    public var severity: DFTDiagnosticSeverity
    public var code: String
    public var message: String
    public var entity: String?
    public var suggestedActions: [String]

    public init(
        severity: DFTDiagnosticSeverity,
        code: String,
        message: String,
        entity: String? = nil,
        suggestedActions: [String] = []
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.entity = entity
        self.suggestedActions = suggestedActions
    }
}
