import Foundation

public struct DFTExternalToolDescriptor: Sendable, Hashable, Codable {
    public var engineID: String
    public var implementationID: String
    public var implementationVersion: String

    public init(
        engineID: String,
        implementationID: String,
        implementationVersion: String
    ) {
        self.engineID = engineID
        self.implementationID = implementationID
        self.implementationVersion = implementationVersion
    }
}
