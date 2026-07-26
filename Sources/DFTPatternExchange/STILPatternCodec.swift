import Foundation

public struct STILPatternCodec: DFTStandardPatternCoding {
    public let capability = DFTStandardPatternCapability(
        profileID: "lsi-stil-1.0-cycle-v1",
        standardVersion: "STIL 1.0",
        textEncoding: "US-ASCII",
        timeUnit: "ps",
        supportedActions: [
            .driveLow,
            .driveHigh,
            .driveHighImpedance,
            .compareLow,
            .compareHigh,
            .mask,
        ],
        supportsSignalGroups: true,
        supportsProcedures: true,
        supportsPatternBursts: true,
        supportsEscapedIdentifiers: false
    )
    private let validator: any DFTPatternExchangeValidating

    public init(
        validator: any DFTPatternExchangeValidating = DFTPatternExchangeValidator()
    ) {
        self.validator = validator
    }

    public func encode(_ program: DFTPatternExchangeProgram) throws -> Data {
        try validator.validate(program)
        var data = Data()
        let cycleCount = program.procedures.reduce(0) { $0 + $1.cycles.count }
        data.reserveCapacity(max(1_024, cycleCount * 128))
        func write(_ line: String) {
            data.append(contentsOf: line.utf8)
            data.append(0x0A)
        }

        write("STIL 1.0;")
        write("Header {")
        write("  Title \"\(program.name)\";")
        write("}")
        write("Signals {")
        for signal in program.signals {
            write("  \"\(signal.name)\" \(stilDirection(signal.direction));")
        }
        write("}")
        write("SignalGroups {")
        for group in program.signalGroups {
            let expression = group.signalNames.map { "\"\($0)\"" }.joined(separator: " + ")
            write("  \"\(group.name)\" = '\(expression)';")
        }
        write("}")
        write("Timing {")
        for timingSet in program.timingSets {
            write("  WaveformTable \"\(timingSet.name)\" {")
            write("    Period '\(timingSet.periodPicoseconds)ps';")
            write("    Waveforms {")
            for waveform in timingSet.waveforms {
                write("      \"\(waveform.signalName)\" {")
                for symbol in waveform.symbols {
                    write("        \"\(symbol.symbol)\" {")
                    for event in symbol.events {
                        write(
                            "          '\(event.offsetPicoseconds)ps' \(stilAction(event.action));"
                        )
                    }
                    write("        }")
                }
                write("      }")
            }
            write("    }")
            write("  }")
        }
        write("}")
        write("Procedures {")
        for procedure in program.procedures {
            write("  \"\(procedure.name)\" {")
            for cycle in procedure.cycles {
                write("    W \"\(cycle.timingSetName)\";")
                write("    V {")
                for assignment in cycle.assignments {
                    write(
                        "      \"\(assignment.target)\" = \(assignment.symbols);"
                    )
                }
                write("    }")
            }
            write("  }")
        }
        write("}")
        let burstName = "\(program.name)_burst"
        write("PatternBurst \"\(burstName)\" {")
        write("  PatList {")
        for pattern in program.patterns {
            write("    \"\(pattern.id)\";")
        }
        write("  }")
        write("}")
        write("PatternExec {")
        write("  PatternBurst \"\(burstName)\";")
        write("}")
        for pattern in program.patterns {
            write("Pattern \"\(pattern.id)\" {")
            for procedureName in pattern.procedureNames {
                write("  Call \"\(procedureName)\";")
            }
            write("}")
        }
        return data
    }

    public func decode(_ data: Data) throws -> DFTPatternExchangeProgram {
        var parser = try STILParser(data: data)
        let program = try parser.parse()
        try validator.validate(program)
        return program
    }

    private func stilDirection(_ direction: DFTPatternSignalDirection) -> String {
        switch direction {
        case .input:
            "In"
        case .output:
            "Out"
        case .bidirectional:
            "InOut"
        }
    }

    private func stilAction(_ action: DFTWaveformAction) -> String {
        switch action {
        case .driveLow:
            "D"
        case .driveHigh:
            "U"
        case .driveHighImpedance:
            "Z"
        case .compareLow:
            "L"
        case .compareHigh:
            "H"
        case .mask:
            "X"
        }
    }
}
