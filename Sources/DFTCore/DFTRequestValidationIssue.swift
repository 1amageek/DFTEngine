import Foundation

public struct DFTRequestValidationIssue: Sendable, Hashable, Codable {
    public var code: String
    public var message: String
    public var entity: String?
    public var suggestedActions: [String]

    public init(
        code: String,
        message: String,
        entity: String? = nil,
        suggestedActions: [String] = []
    ) {
        self.code = code
        self.message = message
        self.entity = entity
        self.suggestedActions = suggestedActions
    }
}
