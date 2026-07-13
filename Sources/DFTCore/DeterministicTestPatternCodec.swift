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
        case .stil:
            return Data(stilText(for: patternSet).utf8)
        case .wgl:
            return Data(wglText(for: patternSet).utf8)
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
            return try parseText(String(decoding: data, as: UTF8.self), format: format)
        }
    }

    private func stilText(for patternSet: DFTTestPatternSet) -> String {
        var lines = [
            "STIL 1.0;",
            "// seed=\(patternSet.seed)",
            "// faultUniverseDigest=\(patternSet.faultUniverseDigest)",
            "PatternBurst \"DFTEngine\" {",
            "  PatList {"
        ]
        for pattern in patternSet.patterns {
            lines.append("    \(pattern.id) { \(pattern.bits); }")
        }
        lines.append(contentsOf: ["  }", "}", ""])
        return lines.joined(separator: "\n")
    }

    private func wglText(for patternSet: DFTTestPatternSet) -> String {
        var lines = [
            "WGL 1.0;",
            "// seed=\(patternSet.seed)",
            "// faultUniverseDigest=\(patternSet.faultUniverseDigest)",
            "Patterns {"
        ]
        for pattern in patternSet.patterns {
            lines.append("  Pattern \"\(pattern.id)\" = \(pattern.bits);")
        }
        lines.append(contentsOf: ["}", ""])
        return lines.joined(separator: "\n")
    }

    private func parseText(
        _ text: String,
        format: DFTTestPatternFormat
    ) throws -> DFTTestPatternSet {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let seed = parseSeedMetadata(from: lines) else {
            throw DFTPatternFormatError.malformedPattern("seed metadata is missing")
        }
        guard let digest = parseDigestMetadata(from: lines) else {
            throw DFTPatternFormatError.malformedPattern("fault-universe digest metadata is missing")
        }
        guard digest.count == 64, digest.allSatisfy({ $0.isHexDigit }) else {
            throw DFTPatternFormatError.malformedPattern("fault-universe digest must be a SHA-256 value")
        }
        try validateContainer(lines: lines, format: format)

        var patterns: [DFTTestPattern] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("//") {
                continue
            }
            if format == .stil {
                if trimmed == "STIL 1.0;"
                    || trimmed.hasPrefix("PatternBurst ")
                    || trimmed == "PatList {"
                    || trimmed == "}"
                {
                    continue
                }
                guard let open = trimmed.firstIndex(of: "{"),
                      let close = trimmed.lastIndex(of: "}"),
                      open < close else {
                    throw DFTPatternFormatError.malformedPattern("STIL pattern declaration is invalid")
                }
                let idSlice = trimmed[..<open].trimmingCharacters(in: .whitespaces)
                let body = trimmed[trimmed.index(after: open)..<close]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard body.hasSuffix(";") else {
                    throw DFTPatternFormatError.malformedPattern("STIL pattern vector must end with ';'")
                }
                let bits = String(body.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                let id = String(idSlice)
                guard isPatternID(id), isBitString(bits) else {
                    throw DFTPatternFormatError.malformedPattern("STIL pattern ID or vector is invalid")
                }
                patterns.append(DFTTestPattern(id: id, bits: bits, faultIDs: []))
                continue
            }
            if trimmed == "WGL 1.0;" || trimmed == "Patterns {" || trimmed == "}" {
                continue
            }
            guard trimmed.hasPrefix("Pattern ") else {
                throw DFTPatternFormatError.malformedPattern("unknown WGL line: \(trimmed)")
            }
            let body = trimmed.dropFirst("Pattern ".count)
            guard let quoteStart = body.firstIndex(of: "\""),
                  let quoteEnd = body[body.index(after: quoteStart)...].firstIndex(of: "\"") else {
                throw DFTPatternFormatError.malformedPattern("WGL pattern name is incomplete")
            }
            let id = String(body[body.index(after: quoteStart)..<quoteEnd])
            let remainder = body[body.index(after: quoteEnd)...]
            guard let equals = remainder.firstIndex(of: "=") else {
                throw DFTPatternFormatError.malformedPattern("WGL pattern \(id) has no vector")
            }
            let vectorText = remainder[remainder.index(after: equals)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard vectorText.hasSuffix(";") else {
                throw DFTPatternFormatError.malformedPattern("WGL pattern \(id) must end with ';'")
            }
            let bits = String(vectorText.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isPatternID(id), isBitString(bits) else {
                throw DFTPatternFormatError.malformedPattern("WGL pattern ID or vector is invalid")
            }
            patterns.append(DFTTestPattern(id: id, bits: bits, faultIDs: []))
        }

        let result = DFTTestPatternSet(
            format: format.rawValue,
            seed: seed,
            faultUniverseDigest: digest,
            patterns: patterns
        )
        try validate(result)
        return result
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
    }

    private func validateContainer(lines: [String], format: DFTTestPatternFormat) throws {
        let normalized = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        switch format {
        case .stil:
            guard normalized.first == "STIL 1.0;",
                  normalized.contains("PatList {"),
                  normalized.last == "}",
                  Array(normalized.dropLast()).last == "}" else {
                throw DFTPatternFormatError.malformedPattern("STIL container is incomplete")
            }
        case .wgl:
            guard normalized.first == "WGL 1.0;",
                  normalized.contains("Patterns {"),
                  normalized.last == "}" else {
                throw DFTPatternFormatError.malformedPattern("WGL container is incomplete")
            }
        case .json:
            break
        }
    }

    private func parseSeedMetadata(from lines: [String]) -> UInt64? {
        guard let line = lines.first(where: { $0.contains("// seed=") }) else {
            return nil
        }
        let value = line.components(separatedBy: "=").dropFirst().joined(separator: "=")
        return UInt64(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func parseDigestMetadata(from lines: [String]) -> String? {
        guard let line = lines.first(where: { $0.contains("// faultUniverseDigest=") }) else {
            return nil
        }
        return line.components(separatedBy: "=").dropFirst().joined(separator: "=")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isPatternID(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }

    private func isBitString(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0 == "0" || $0 == "1" }
    }
}
