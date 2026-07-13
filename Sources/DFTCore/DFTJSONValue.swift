import Foundation

public enum DFTJSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([DFTJSONValue])
    case object([String: DFTJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else {
            do { self = .bool(try container.decode(Bool.self)); return }
            catch {}
            do { self = .number(try container.decode(Double.self)); return }
            catch {}
            do { self = .string(try container.decode(String.self)); return }
            catch {}
            do { self = .array(try container.decode([DFTJSONValue].self)); return }
            catch {}
            self = .object(try container.decode([String: DFTJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
