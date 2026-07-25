import Foundation

public struct DeterministicTestPatternCodec: DFTTestPatternCoding {
    public init() {}

    public func encode(
        _ patternSet: DFTTestPatternSet,
        format: DFTTestPatternFormat
    ) throws -> Data {
        try validate(patternSet)
        switch format {
        case .json:
            return try DFTArtifactJSONEncoder().encode(patternSet)
        case .stil, .wgl:
            throw DFTPatternFormatError.unsupportedFormat(format.rawValue)
        }
    }

    public func decode(
        _ data: Data,
        format: DFTTestPatternFormat
    ) throws -> DFTTestPatternSet {
        switch format {
        case .json:
            do {
                let patternSet = try JSONDecoder().decode(DFTTestPatternSet.self, from: data)
                try validate(patternSet)
                guard patternSet.format == DFTTestPatternFormat.json.rawValue else {
                    throw DFTPatternFormatError.malformedPattern("JSON pattern format marker is invalid")
                }
                return patternSet
            } catch let error as DFTPatternFormatError {
                throw error
            } catch {
                throw DFTPatternFormatError.malformedPattern(error.localizedDescription)
            }
        case .stil, .wgl:
            throw DFTPatternFormatError.unsupportedFormat(format.rawValue)
        }
    }

    private func validate(_ patternSet: DFTTestPatternSet) throws {
        guard !patternSet.patterns.isEmpty else {
            throw DFTPatternFormatError.emptyPatternSet
        }
        guard patternSet.faultUniverseDigest.count == 64,
              patternSet.faultUniverseDigest.allSatisfy({ $0.isHexDigit }) else {
            throw DFTPatternFormatError.malformedPattern("fault-universe digest must be a SHA-256 value")
        }
        let ids = patternSet.patterns.map(\.id)
        guard ids.allSatisfy(isPatternID), Set(ids).count == ids.count else {
            throw DFTPatternFormatError.malformedPattern("pattern IDs must be non-empty and unique")
        }
        guard patternSet.patterns.allSatisfy({ isBitString($0.bits) }) else {
            throw DFTPatternFormatError.malformedPattern("pattern vectors must contain only binary values")
        }
        guard Set(patternSet.patterns.map { $0.bits.count }).count == 1 else {
            throw DFTPatternFormatError.malformedPattern("all pattern vectors must have the same width")
        }
        for pattern in patternSet.patterns {
            guard pattern.faultIDs.allSatisfy({ !$0.isEmpty }),
                  Set(pattern.faultIDs).count == pattern.faultIDs.count else {
                throw DFTPatternFormatError.malformedPattern(
                    "fault IDs for pattern \(pattern.id) must be non-empty and unique"
                )
            }
        }
    }

    private func isPatternID(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }

    private func isBitString(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0 == "0" || $0 == "1" }
    }
}
