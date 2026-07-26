public struct DFTPatternExchangeValidator: DFTPatternExchangeValidating {
    public init() {}

    public func validate(_ program: DFTPatternExchangeProgram) throws {
        guard program.schemaVersion == 1 else {
            throw DFTPatternExchangeError.unsupportedSchemaVersion(program.schemaVersion)
        }
        try validateIdentifier(program.name, context: "program")
        try requireNonempty(program.signals, context: "signals")
        try requireNonempty(program.timingSets, context: "timingSets")
        try requireNonempty(program.procedures, context: "procedures")
        try requireNonempty(program.patterns, context: "patterns")

        try validateUnique(program.signals.map(\.name), context: "signals")
        try validateUnique(program.signalGroups.map(\.name), context: "signalGroups")
        try validateUnique(program.timingSets.map(\.name), context: "timingSets")
        try validateUnique(program.procedures.map(\.name), context: "procedures")
        try validateUnique(program.patterns.map(\.id), context: "patterns")

        let signalByName = Dictionary(uniqueKeysWithValues: program.signals.map { ($0.name, $0) })
        let groupByName = Dictionary(uniqueKeysWithValues: program.signalGroups.map { ($0.name, $0) })
        let signalNames = Set(signalByName.keys)
        let groupNames = Set(groupByName.keys)
        guard signalNames.isDisjoint(with: groupNames) else {
            let duplicate = signalNames.intersection(groupNames).sorted()[0]
            throw DFTPatternExchangeError.duplicateIdentifier(context: "signals and groups", value: duplicate)
        }

        for signal in program.signals {
            try validateIdentifier(signal.name, context: "signal")
        }
        for group in program.signalGroups {
            try validateIdentifier(group.name, context: "signal group")
            try requireNonempty(group.signalNames, context: "signal group \(group.name)")
            try validateUnique(group.signalNames, context: "signal group \(group.name)")
            for signalName in group.signalNames where signalByName[signalName] == nil {
                throw DFTPatternExchangeError.unknownReference(
                    context: "signal group \(group.name)",
                    value: signalName
                )
            }
        }

        let timingByName = try validateTimingSets(program.timingSets, signals: signalByName)
        try validateProcedures(
            program.procedures,
            signals: signalByName,
            groups: groupByName,
            timingSets: timingByName
        )

        let procedureNames = Set(program.procedures.map(\.name))
        for pattern in program.patterns {
            try validateIdentifier(pattern.id, context: "pattern")
            try requireNonempty(pattern.procedureNames, context: "pattern \(pattern.id)")
            for procedureName in pattern.procedureNames where !procedureNames.contains(procedureName) {
                throw DFTPatternExchangeError.unknownReference(
                    context: "pattern \(pattern.id)",
                    value: procedureName
                )
            }
        }
    }

    private func validateTimingSets(
        _ timingSets: [DFTPatternTimingSet],
        signals: [String: DFTPatternSignal]
    ) throws -> [String: DFTPatternTimingSet] {
        for timingSet in timingSets {
            try validateIdentifier(timingSet.name, context: "timing set")
            guard timingSet.periodPicoseconds > 0 else {
                throw DFTPatternExchangeError.invalidPeriod(timingSet: timingSet.name)
            }
            try validateUnique(
                timingSet.waveforms.map(\.signalName),
                context: "timing set \(timingSet.name) waveforms"
            )
            let waveformNames = Set(timingSet.waveforms.map(\.signalName))
            let missingWaveforms = Set(signals.keys).subtracting(waveformNames)
            guard missingWaveforms.isEmpty, waveformNames.count == signals.count else {
                throw DFTPatternExchangeError.incompleteCycle(
                    procedure: "timing set \(timingSet.name)",
                    missingSignals: missingWaveforms.sorted()
                )
            }
            for waveform in timingSet.waveforms {
                guard let signal = signals[waveform.signalName] else {
                    throw DFTPatternExchangeError.unknownReference(
                        context: "timing set \(timingSet.name)",
                        value: waveform.signalName
                    )
                }
                try validateWaveform(waveform, signal: signal, timingSet: timingSet)
            }
        }
        return Dictionary(uniqueKeysWithValues: timingSets.map { ($0.name, $0) })
    }

    private func validateWaveform(
        _ waveform: DFTSignalWaveform,
        signal: DFTPatternSignal,
        timingSet: DFTPatternTimingSet
    ) throws {
        try requireNonempty(
            waveform.symbols,
            context: "waveform \(timingSet.name).\(waveform.signalName)"
        )
        try validateUnique(
            waveform.symbols.map(\.symbol),
            context: "waveform \(timingSet.name).\(waveform.signalName)"
        )
        for symbol in waveform.symbols {
            guard symbol.symbol.count == 1, symbol.symbol.first?.isWhitespace == false else {
                throw DFTPatternExchangeError.invalidWaveformSymbol(
                    signal: signal.name,
                    symbol: symbol.symbol
                )
            }
            try requireNonempty(
                symbol.events,
                context: "waveform \(timingSet.name).\(signal.name).\(symbol.symbol)"
            )
            var previousOffset: UInt64?
            for event in symbol.events {
                guard event.offsetPicoseconds < timingSet.periodPicoseconds else {
                    throw DFTPatternExchangeError.invalidWaveformEvent(
                        signal: signal.name,
                        symbol: symbol.symbol,
                        reason: "event offset is outside the timing period"
                    )
                }
                if let previousOffset, event.offsetPicoseconds <= previousOffset {
                    throw DFTPatternExchangeError.invalidWaveformEvent(
                        signal: signal.name,
                        symbol: symbol.symbol,
                        reason: "event offsets must be strictly increasing"
                    )
                }
                try validate(event.action, for: signal, symbol: symbol.symbol)
                previousOffset = event.offsetPicoseconds
            }
        }
    }

    private func validate(
        _ action: DFTWaveformAction,
        for signal: DFTPatternSignal,
        symbol: String
    ) throws {
        let isDrive = action == .driveLow || action == .driveHigh || action == .driveHighImpedance
        let isCompare = action == .compareLow || action == .compareHigh || action == .mask
        if isDrive && signal.direction == .output {
            throw DFTPatternExchangeError.invalidWaveformEvent(
                signal: signal.name,
                symbol: symbol,
                reason: "an output-only signal cannot use a drive action"
            )
        }
        if isCompare && signal.direction == .input {
            throw DFTPatternExchangeError.invalidWaveformEvent(
                signal: signal.name,
                symbol: symbol,
                reason: "an input-only signal cannot use a compare action"
            )
        }
    }

    private func validateProcedures(
        _ procedures: [DFTPatternProcedure],
        signals: [String: DFTPatternSignal],
        groups: [String: DFTPatternSignalGroup],
        timingSets: [String: DFTPatternTimingSet]
    ) throws {
        for procedure in procedures {
            try validateIdentifier(procedure.name, context: "procedure")
            try requireNonempty(procedure.cycles, context: "procedure \(procedure.name)")
            for cycle in procedure.cycles {
                guard let timingSet = timingSets[cycle.timingSetName] else {
                    throw DFTPatternExchangeError.unknownReference(
                        context: "procedure \(procedure.name)",
                        value: cycle.timingSetName
                    )
                }
                try validateCycle(
                    cycle,
                    procedure: procedure.name,
                    signals: signals,
                    groups: groups,
                    timingSet: timingSet
                )
            }
        }
    }

    private func validateCycle(
        _ cycle: DFTPatternCycle,
        procedure: String,
        signals: [String: DFTPatternSignal],
        groups: [String: DFTPatternSignalGroup],
        timingSet: DFTPatternTimingSet
    ) throws {
        try requireNonempty(cycle.assignments, context: "procedure \(procedure) cycle")
        try validateUnique(cycle.assignments.map(\.target), context: "procedure \(procedure) cycle")
        let waveformBySignal = Dictionary(
            uniqueKeysWithValues: timingSet.waveforms.map { ($0.signalName, $0) }
        )
        var assignedSignals = Set<String>()
        for assignment in cycle.assignments {
            let expandedSignals: [String]
            if signals[assignment.target] != nil {
                expandedSignals = [assignment.target]
            } else if let group = groups[assignment.target] {
                expandedSignals = group.signalNames
            } else {
                throw DFTPatternExchangeError.unknownReference(
                    context: "procedure \(procedure) assignment",
                    value: assignment.target
                )
            }
            guard assignment.symbols.count == expandedSignals.count else {
                throw DFTPatternExchangeError.invalidAssignment(
                    procedure: procedure,
                    target: assignment.target,
                    reason: "symbol width does not match the target width"
                )
            }
            for (signalName, symbol) in zip(expandedSignals, assignment.symbols) {
                guard assignedSignals.insert(signalName).inserted else {
                    throw DFTPatternExchangeError.invalidAssignment(
                        procedure: procedure,
                        target: assignment.target,
                        reason: "the assignment overlaps another target"
                    )
                }
                guard let waveform = waveformBySignal[signalName] else {
                    throw DFTPatternExchangeError.unknownReference(
                        context: "timing set \(timingSet.name) waveform",
                        value: signalName
                    )
                }
                let supportedSymbols = Set(waveform.symbols.map(\.symbol))
                guard supportedSymbols.contains(String(symbol)) else {
                    throw DFTPatternExchangeError.invalidAssignment(
                        procedure: procedure,
                        target: assignment.target,
                        reason: "symbol \(symbol) has no waveform for signal \(signalName)"
                    )
                }
            }
        }
        let missing = Set(signals.keys).subtracting(assignedSignals).sorted()
        guard missing.isEmpty else {
            throw DFTPatternExchangeError.incompleteCycle(
                procedure: procedure,
                missingSignals: missing
            )
        }
    }

    private func validateIdentifier(_ value: String, context: String) throws {
        guard let first = value.first,
              first.isLetter || first == "_",
              value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }) else {
            throw DFTPatternExchangeError.invalidIdentifier(context: context, value: value)
        }
    }

    private func validateUnique(_ values: [String], context: String) throws {
        var seen = Set<String>()
        for value in values where !seen.insert(value).inserted {
            throw DFTPatternExchangeError.duplicateIdentifier(context: context, value: value)
        }
    }

    private func requireNonempty<Element>(_ values: [Element], context: String) throws {
        guard !values.isEmpty else {
            throw DFTPatternExchangeError.emptyCollection(context)
        }
    }
}
