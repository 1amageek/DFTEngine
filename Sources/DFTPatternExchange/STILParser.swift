import Foundation

struct STILParser {
    private var lexer: STILLexer
    private var current: (token: STILToken, offset: Int)?

    init(data: Data) throws {
        var lexer = STILLexer(data: data)
        current = try lexer.nextToken()
        self.lexer = lexer
    }

    mutating func parse() throws -> DFTPatternExchangeProgram {
        try expectWord("STIL")
        try expectWord("1.0")
        try expect(.semicolon)
        let name = try parseHeader()
        let signals = try parseSignals()
        let groups = try parseSignalGroups()
        let timingSets = try parseTiming()
        let procedures = try parseProcedures()
        let burst = try parsePatternBurst(expectedName: "\(name)_burst")
        try parsePatternExec(expectedBurst: "\(name)_burst")
        let patterns = try parsePatterns()
        guard patterns.map(\.id) == burst else {
            throw malformed("PatternBurst order does not match Pattern declarations")
        }
        guard current == nil else {
            throw unsupportedCurrentToken()
        }
        return DFTPatternExchangeProgram(
            name: name,
            signals: signals,
            signalGroups: groups,
            timingSets: timingSets,
            procedures: procedures,
            patterns: patterns
        )
    }

    private mutating func parseHeader() throws -> String {
        try expectWord("Header")
        try expect(.leftBrace)
        try expectWord("Title")
        let title = try readQuoted()
        try expect(.semicolon)
        try expect(.rightBrace)
        return title
    }

    private mutating func parseSignals() throws -> [DFTPatternSignal] {
        try expectWord("Signals")
        try expect(.leftBrace)
        var signals: [DFTPatternSignal] = []
        while !matches(.rightBrace) {
            let name = try readQuoted()
            let directionWord = try readWord()
            let direction: DFTPatternSignalDirection
            switch directionWord {
            case "In":
                direction = .input
            case "Out":
                direction = .output
            case "InOut":
                direction = .bidirectional
            default:
                throw unsupported(directionWord)
            }
            try expect(.semicolon)
            signals.append(DFTPatternSignal(name: name, direction: direction))
        }
        try expect(.rightBrace)
        return signals
    }

    private mutating func parseSignalGroups() throws -> [DFTPatternSignalGroup] {
        try expectWord("SignalGroups")
        try expect(.leftBrace)
        var groups: [DFTPatternSignalGroup] = []
        while !matches(.rightBrace) {
            let name = try readQuoted()
            try expect(.equal)
            let expression = try readSingleQuoted()
            try expect(.semicolon)
            groups.append(
                DFTPatternSignalGroup(
                    name: name,
                    signalNames: try parseGroupExpression(expression)
                )
            )
        }
        try expect(.rightBrace)
        return groups
    }

    private func parseGroupExpression(_ expression: String) throws -> [String] {
        var lexer = STILLexer(data: Data(expression.utf8))
        var expressionTokens: [(token: STILToken, offset: Int)] = []
        while let token = try lexer.nextToken() {
            expressionTokens.append(token)
        }
        var names: [String] = []
        for (position, item) in expressionTokens.enumerated() {
            if position.isMultiple(of: 2) {
                guard case let .quoted(name) = item.token else {
                    throw DFTPatternExchangeError.malformedSTIL(
                        offset: item.offset,
                        reason: "signal-group expression requires quoted signal names"
                    )
                }
                names.append(name)
            } else {
                guard item.token == .word("+") else {
                    throw DFTPatternExchangeError.unsupportedSTILConstruct(
                        keyword: "signal-group operator",
                        offset: item.offset
                    )
                }
            }
        }
        guard !names.isEmpty, expressionTokens.count == names.count * 2 - 1 else {
            throw DFTPatternExchangeError.malformedSTIL(
                offset: 0,
                reason: "signal-group expression is empty or incomplete"
            )
        }
        return names
    }

    private mutating func parseTiming() throws -> [DFTPatternTimingSet] {
        try expectWord("Timing")
        try expect(.leftBrace)
        var timingSets: [DFTPatternTimingSet] = []
        while !matches(.rightBrace) {
            try expectWord("WaveformTable")
            let name = try readQuoted()
            try expect(.leftBrace)
            try expectWord("Period")
            let period = try parsePicoseconds(try readSingleQuoted())
            try expect(.semicolon)
            try expectWord("Waveforms")
            try expect(.leftBrace)
            var waveforms: [DFTSignalWaveform] = []
            while !matches(.rightBrace) {
                waveforms.append(try parseWaveform())
            }
            try expect(.rightBrace)
            try expect(.rightBrace)
            timingSets.append(
                DFTPatternTimingSet(
                    name: name,
                    periodPicoseconds: period,
                    waveforms: waveforms
                )
            )
        }
        try expect(.rightBrace)
        return timingSets
    }

    private mutating func parseWaveform() throws -> DFTSignalWaveform {
        let signalName = try readQuoted()
        try expect(.leftBrace)
        var symbols: [DFTWaveformSymbol] = []
        while !matches(.rightBrace) {
            let symbol = try readQuoted()
            try expect(.leftBrace)
            var events: [DFTWaveformEvent] = []
            while !matches(.rightBrace) {
                let offset = try parsePicoseconds(try readSingleQuoted())
                let action = try parseAction(try readWord())
                try expect(.semicolon)
                events.append(DFTWaveformEvent(offsetPicoseconds: offset, action: action))
            }
            try expect(.rightBrace)
            symbols.append(DFTWaveformSymbol(symbol: symbol, events: events))
        }
        try expect(.rightBrace)
        return DFTSignalWaveform(signalName: signalName, symbols: symbols)
    }

    private func parsePicoseconds(_ value: String) throws -> UInt64 {
        guard value.hasSuffix("ps"),
              let result = UInt64(value.dropLast(2)) else {
            throw DFTPatternExchangeError.unsupportedSTILConstruct(
                keyword: "non-picosecond time literal",
                offset: currentOffset
            )
        }
        return result
    }

    private func parseAction(_ value: String) throws -> DFTWaveformAction {
        switch value {
        case "D":
            return .driveLow
        case "U":
            return .driveHigh
        case "Z":
            return .driveHighImpedance
        case "L":
            return .compareLow
        case "H":
            return .compareHigh
        case "X":
            return .mask
        default:
            throw DFTPatternExchangeError.unsupportedSTILConstruct(
                keyword: "waveform action \(value)",
                offset: currentOffset
            )
        }
    }

    private mutating func parseProcedures() throws -> [DFTPatternProcedure] {
        try expectWord("Procedures")
        try expect(.leftBrace)
        var procedures: [DFTPatternProcedure] = []
        while !matches(.rightBrace) {
            let name = try readQuoted()
            try expect(.leftBrace)
            var cycles: [DFTPatternCycle] = []
            while !matches(.rightBrace) {
                try expectWord("W")
                let timingSet = try readQuoted()
                try expect(.semicolon)
                try expectWord("V")
                try expect(.leftBrace)
                var assignments: [DFTPatternAssignment] = []
                while !matches(.rightBrace) {
                    let target = try readQuoted()
                    try expect(.equal)
                    let symbols = try readWord()
                    try expect(.semicolon)
                    assignments.append(
                        DFTPatternAssignment(target: target, symbols: symbols)
                    )
                }
                try expect(.rightBrace)
                cycles.append(
                    DFTPatternCycle(
                        timingSetName: timingSet,
                        assignments: assignments
                    )
                )
            }
            try expect(.rightBrace)
            procedures.append(DFTPatternProcedure(name: name, cycles: cycles))
        }
        try expect(.rightBrace)
        return procedures
    }

    private mutating func parsePatternBurst(expectedName: String) throws -> [String] {
        try expectWord("PatternBurst")
        let name = try readQuoted()
        guard name == expectedName else {
            throw malformed("PatternBurst name does not match the program name")
        }
        try expect(.leftBrace)
        try expectWord("PatList")
        try expect(.leftBrace)
        var patterns: [String] = []
        while !matches(.rightBrace) {
            patterns.append(try readQuoted())
            try expect(.semicolon)
        }
        try expect(.rightBrace)
        try expect(.rightBrace)
        return patterns
    }

    private mutating func parsePatternExec(expectedBurst: String) throws {
        try expectWord("PatternExec")
        try expect(.leftBrace)
        try expectWord("PatternBurst")
        let burst = try readQuoted()
        guard burst == expectedBurst else {
            throw malformed("PatternExec references a different PatternBurst")
        }
        try expect(.semicolon)
        try expect(.rightBrace)
    }

    private mutating func parsePatterns() throws -> [DFTPatternCase] {
        var patterns: [DFTPatternCase] = []
        while current != nil {
            try expectWord("Pattern")
            let id = try readQuoted()
            try expect(.leftBrace)
            var procedures: [String] = []
            while !matches(.rightBrace) {
                try expectWord("Call")
                procedures.append(try readQuoted())
                try expect(.semicolon)
            }
            try expect(.rightBrace)
            patterns.append(DFTPatternCase(id: id, procedureNames: procedures))
        }
        return patterns
    }

    private mutating func expectWord(_ expected: String) throws {
        let value = try readWord()
        guard value == expected else {
            throw unsupported(value)
        }
    }

    private mutating func readWord() throws -> String {
        guard let current, case let .word(value) = current.token else {
            throw malformed("expected a keyword or unquoted value")
        }
        try advance()
        return value
    }

    private mutating func readQuoted() throws -> String {
        guard let current, case let .quoted(value) = current.token else {
            throw malformed("expected a quoted identifier")
        }
        try advance()
        return value
    }

    private mutating func readSingleQuoted() throws -> String {
        guard let current, case let .singleQuoted(value) = current.token else {
            throw malformed("expected a single-quoted expression")
        }
        try advance()
        return value
    }

    private mutating func expect(_ token: STILToken) throws {
        guard current?.token == token else {
            throw malformed("expected \(token)")
        }
        try advance()
    }

    private func matches(_ token: STILToken) -> Bool {
        current?.token == token
    }

    private var currentOffset: Int {
        current?.offset ?? 0
    }

    private func malformed(_ reason: String) -> DFTPatternExchangeError {
        .malformedSTIL(offset: currentOffset, reason: reason)
    }

    private func unsupported(_ keyword: String) -> DFTPatternExchangeError {
        .unsupportedSTILConstruct(keyword: keyword, offset: currentOffset)
    }

    private func unsupportedCurrentToken() -> DFTPatternExchangeError {
        .unsupportedSTILConstruct(
            keyword: String(describing: current?.token),
            offset: currentOffset
        )
    }

    private mutating func advance() throws {
        current = try lexer.nextToken()
    }
}
