import Foundation

struct STILLexer {
    private let data: Data
    private var index: Int

    init(data: Data) {
        self.data = data
        index = data.startIndex
    }

    mutating func nextToken() throws -> (token: STILToken, offset: Int)? {
        try skipTrivia()
        guard index < data.endIndex else {
            return nil
        }
        let offset = index
        let token: STILToken
        switch data[index] {
        case 0x7B:
            index += 1
            token = .leftBrace
        case 0x7D:
            index += 1
            token = .rightBrace
        case 0x3B:
            index += 1
            token = .semicolon
        case 0x3D:
            index += 1
            token = .equal
        case 0x22:
            token = .quoted(try readQuoted(delimiter: 0x22))
        case 0x27:
            token = .singleQuoted(try readQuoted(delimiter: 0x27))
        default:
            token = .word(try readWord())
        }
        return (token, offset)
    }

    private mutating func skipTrivia() throws {
        while index < data.endIndex {
            let byte = data[index]
            try requireASCII(byte, offset: index)
            if isWhitespace(byte) {
                index += 1
                continue
            }
            if byte == 0x2F, index + 1 < data.endIndex,
               data[index + 1] == 0x2F {
                index += 2
                while index < data.endIndex, data[index] != 0x0A {
                    try requireASCII(data[index], offset: index)
                    index += 1
                }
                continue
            }
            if byte == 0x2F, index + 1 < data.endIndex,
               data[index + 1] == 0x2A {
                let commentOffset = index
                index += 2
                while index + 1 < data.endIndex,
                      !(data[index] == 0x2A && data[index + 1] == 0x2F) {
                    try requireASCII(data[index], offset: index)
                    index += 1
                }
                guard index + 1 < data.endIndex else {
                    throw DFTPatternExchangeError.malformedSTIL(
                        offset: commentOffset,
                        reason: "unterminated block comment"
                    )
                }
                index += 2
                continue
            }
            return
        }
    }

    private mutating func readQuoted(delimiter: UInt8) throws -> String {
        let openingOffset = index
        index += 1
        let start = index
        while index < data.endIndex {
            let byte = data[index]
            try requireASCII(byte, offset: index)
            if byte == delimiter {
                let value = String(decoding: data[start..<index], as: UTF8.self)
                index += 1
                return value
            }
            guard byte != 0x5C else {
                throw DFTPatternExchangeError.unsupportedSTILConstruct(
                    keyword: "escaped string",
                    offset: index
                )
            }
            index += 1
        }
        throw DFTPatternExchangeError.malformedSTIL(
            offset: openingOffset,
            reason: "unterminated quoted value"
        )
    }

    private mutating func readWord() throws -> String {
        let start = index
        while index < data.endIndex {
            let byte = data[index]
            try requireASCII(byte, offset: index)
            if isWhitespace(byte) || isDelimiter(byte) {
                break
            }
            index += 1
        }
        guard index > start else {
            throw DFTPatternExchangeError.malformedSTIL(
                offset: start,
                reason: "unexpected byte \(data[index])"
            )
        }
        return String(decoding: data[start..<index], as: UTF8.self)
    }

    private func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private func isDelimiter(_ byte: UInt8) -> Bool {
        byte == 0x7B
            || byte == 0x7D
            || byte == 0x3B
            || byte == 0x3D
            || byte == 0x22
            || byte == 0x27
    }

    private func requireASCII(_ byte: UInt8, offset: Int) throws {
        guard byte < 0x80 else {
            throw DFTPatternExchangeError.invalidTextEncoding
        }
    }
}
