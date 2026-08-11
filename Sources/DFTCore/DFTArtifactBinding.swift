import CircuiteFoundation
import Foundation

public enum DFTArtifactBindingError: Error, Sendable, Equatable {
    case emptyLogicalID
    case availabilityIdentityMismatch
    case missingBinding(ArtifactID)
    case localAvailabilityRequired(String)
}

/// Binds location-independent artifact identity to one execution-scoped availability.
public struct DFTArtifactBinding: Sendable, Hashable, Codable {
    public let logicalID: String
    public let reference: ArtifactReference
    public let availability: ArtifactAvailability

    public init(
        logicalID: String,
        reference: ArtifactReference,
        availability: ArtifactAvailability
    ) throws {
        guard !logicalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DFTArtifactBindingError.emptyLogicalID
        }
        guard reference.id == availability.artifactID else {
            throw DFTArtifactBindingError.availabilityIdentityMismatch
        }
        self.logicalID = logicalID
        self.reference = reference
        self.availability = availability
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            logicalID: container.decode(String.self, forKey: .logicalID),
            reference: container.decode(ArtifactReference.self, forKey: .reference),
            availability: container.decode(ArtifactAvailability.self, forKey: .availability)
        )
    }

    public var descriptor: ArtifactDescriptor { reference.descriptor }

    public var materializationDescription: String {
        switch availability {
        case .local(_, let rootID, let relativePath):
            "local:\(rootID.rawValue)/\(relativePath.stringValue)"
        case .service(_, let resource):
            "service:\(resource)"
        }
    }

    public func requireLocalRelativePath() throws -> ArtifactRelativePath {
        guard case .local(_, _, let relativePath) = availability else {
            throw DFTArtifactBindingError.localAvailabilityRequired(logicalID)
        }
        return relativePath
    }

    public static func require(
        _ reference: ArtifactReference,
        in bindings: [DFTArtifactBinding]
    ) throws -> DFTArtifactBinding {
        guard let binding = bindings.first(where: { $0.reference == reference }) else {
            throw DFTArtifactBindingError.missingBinding(reference.id)
        }
        return binding
    }
}
