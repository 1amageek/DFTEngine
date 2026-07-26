import DFTPatternExchange
import Foundation

struct VerilogDFTReplayHarnessBuilder: Sendable {
    func build(
        program: DFTPatternExchangeProgram,
        topModule: String,
        faults: [DFTScanPatternReplayFault]
    ) throws -> Data {
        guard isIdentifier(topModule) else {
            throw DFTScanPatternReplayError.harnessGenerationFailed(
                "top module must be an unescaped Verilog identifier"
            )
        }
        try DFTPatternExchangeValidator().validate(program)
        try validateSignals(program.signals)
        try validateFaults(faults)

        let procedures = Dictionary(
            uniqueKeysWithValues: program.procedures.map { ($0.name, $0) }
        )
        var lines = [
            "`timescale 1ps/1ps",
            "module dft_replay_harness;",
        ]
        for signal in program.signals {
            switch signal.direction {
            case .input:
                lines.append("  reg \(signal.name);")
            case .output:
                lines.append("  wire \(signal.name);")
            case .bidirectional:
                throw DFTScanPatternReplayError.harnessGenerationFailed(
                    "bidirectional signal \(signal.name) is unsupported"
                )
            }
        }
        lines.append("  integer dft_fault_index;")
        lines.append("  integer dft_mismatch_count;")
        lines.append("  integer dft_unknown_count;")
        lines.append("  \(topModule) dut (")
        for (index, signal) in program.signals.enumerated() {
            let suffix = index == program.signals.count - 1 ? "" : ","
            lines.append("    .\(signal.name)(\(signal.name))\(suffix)")
        }
        lines.append("  );")
        lines.append("")
        lines.append("  initial begin")
        lines.append("    dft_mismatch_count = 0;")
        lines.append("    dft_unknown_count = 0;")
        lines.append("    if (!$value$plusargs(\"DFT_FAULT_INDEX=%d\", dft_fault_index)) begin")
        lines.append("      dft_fault_index = -1;")
        lines.append("    end")
        for signal in program.signals where signal.direction == .input {
            lines.append("    \(signal.name) = 1'b0;")
        }
        lines.append("    #0;")
        appendFaultApplication(faults, to: &lines)

        var cycleIndex = 0
        for pattern in program.patterns {
            lines.append("    $display(\"DFT_PATTERN_BEGIN \(verilogString(pattern.id))\");")
            for procedureName in pattern.procedureNames {
                guard let procedure = procedures[procedureName] else {
                    throw DFTScanPatternReplayError.harnessGenerationFailed(
                        "pattern \(pattern.id) references missing procedure \(procedureName)"
                    )
                }
                for cycle in procedure.cycles {
                    try append(
                        cycle: cycle,
                        cycleIndex: cycleIndex,
                        patternID: pattern.id,
                        program: program,
                        to: &lines
                    )
                    cycleIndex += 1
                }
            }
        }
        appendFaultRelease(faults, to: &lines)
        lines.append("    if (dft_unknown_count != 0) begin")
        lines.append("      $fatal(1, \"DFT_REPLAY_UNKNOWN_COMPARE count=%0d\", dft_unknown_count);")
        lines.append("    end")
        lines.append("    if (dft_fault_index < 0) begin")
        lines.append("      if (dft_mismatch_count != 0) begin")
        lines.append("        $fatal(1, \"DFT_REPLAY_GOLDEN_MISMATCH count=%0d\", dft_mismatch_count);")
        lines.append("      end")
        lines.append("      $display(\"DFT_REPLAY_GOLDEN_COMPLETE\");")
        lines.append("    end else begin")
        lines.append("      $display(\"DFT_REPLAY_RESULT index=%0d mismatches=%0d\", dft_fault_index, dft_mismatch_count);")
        lines.append("    end")
        lines.append("    $finish;")
        lines.append("  end")
        lines.append("endmodule")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private func append(
        cycle: DFTPatternCycle,
        cycleIndex: Int,
        patternID: String,
        program: DFTPatternExchangeProgram,
        to lines: inout [String]
    ) throws {
        guard let timing = program.timingSets.first(where: {
            $0.name == cycle.timingSetName
        }) else {
            throw DFTScanPatternReplayError.harnessGenerationFailed(
                "cycle references missing timing set \(cycle.timingSetName)"
            )
        }
        let assignments = try expandedAssignments(cycle, program: program)
        var events: [ReplayEvent] = []
        for (signalIndex, signal) in program.signals.enumerated() {
            guard let symbol = assignments[signal.name],
                  let waveform = timing.waveforms.first(where: {
                      $0.signalName == signal.name
                  }),
                  let waveformSymbol = waveform.symbols.first(where: {
                      $0.symbol == symbol
                  }) else {
                throw DFTScanPatternReplayError.harnessGenerationFailed(
                    "signal \(signal.name) has no waveform for symbol \(symbolOrMissing(assignments[signal.name]))"
                )
            }
            for event in waveformSymbol.events {
                let priority: Int
                let statement: String?
                switch event.action {
                case .driveLow:
                    priority = 0
                    statement = "\(signal.name) = 1'b0;"
                case .driveHigh:
                    priority = 0
                    statement = "\(signal.name) = 1'b1;"
                case .driveHighImpedance:
                    priority = 0
                    statement = "\(signal.name) = 1'bz;"
                case .compareLow:
                    priority = 1
                    statement = comparison(
                        signal: signal.name,
                        expected: "1'b0",
                        patternID: patternID,
                        cycleIndex: cycleIndex
                    )
                case .compareHigh:
                    priority = 1
                    statement = comparison(
                        signal: signal.name,
                        expected: "1'b1",
                        patternID: patternID,
                        cycleIndex: cycleIndex
                    )
                case .mask:
                    priority = 2
                    statement = nil
                }
                if let statement {
                    events.append(
                        ReplayEvent(
                            offset: event.offsetPicoseconds,
                            priority: priority,
                            signalIndex: signalIndex,
                            statement: statement
                        )
                    )
                }
            }
        }
        events.sort {
            ($0.offset, $0.priority, $0.signalIndex)
                < ($1.offset, $1.priority, $1.signalIndex)
        }
        var elapsed: UInt64 = 0
        for event in events {
            guard event.offset >= elapsed, event.offset < timing.periodPicoseconds else {
                throw DFTScanPatternReplayError.harnessGenerationFailed(
                    "cycle event offset is outside its timing period"
                )
            }
            let delay = event.offset - elapsed
            if delay > 0 {
                lines.append("    #\(delay);")
            }
            lines.append(contentsOf: event.statement.split(separator: "\n").map {
                "    " + String($0)
            })
            elapsed = event.offset
        }
        let remaining = timing.periodPicoseconds - elapsed
        if remaining > 0 {
            lines.append("    #\(remaining);")
        }
    }

    private func expandedAssignments(
        _ cycle: DFTPatternCycle,
        program: DFTPatternExchangeProgram
    ) throws -> [String: String] {
        let groups = Dictionary(
            uniqueKeysWithValues: program.signalGroups.map {
                ($0.name, $0.signalNames)
            }
        )
        var result: [String: String] = [:]
        for assignment in cycle.assignments {
            let targetSignals = groups[assignment.target] ?? [assignment.target]
            let symbols = assignment.symbols.map(String.init)
            guard targetSignals.count == symbols.count else {
                throw DFTScanPatternReplayError.harnessGenerationFailed(
                    "assignment \(assignment.target) width does not match its symbols"
                )
            }
            for (signal, symbol) in zip(targetSignals, symbols) {
                guard result[signal] == nil else {
                    throw DFTScanPatternReplayError.harnessGenerationFailed(
                        "cycle assigns signal \(signal) more than once"
                    )
                }
                result[signal] = symbol
            }
        }
        return result
    }

    private func comparison(
        signal: String,
        expected: String,
        patternID: String,
        cycleIndex: Int
    ) -> String {
        """
        if ((\(signal) !== 1'b0) && (\(signal) !== 1'b1)) begin
          dft_unknown_count = dft_unknown_count + 1;
          $display("DFT_UNKNOWN_COMPARE pattern=\(verilogString(patternID)) cycle=\(cycleIndex) signal=\(signal)");
        end else if (\(signal) !== \(expected)) begin
          dft_mismatch_count = dft_mismatch_count + 1;
          $display("DFT_COMPARE_MISMATCH pattern=\(verilogString(patternID)) cycle=\(cycleIndex) signal=\(signal)");
        end
        """
    }

    private func appendFaultApplication(
        _ faults: [DFTScanPatternReplayFault],
        to lines: inout [String]
    ) {
        guard !faults.isEmpty else { return }
        lines.append("    case (dft_fault_index)")
        for (index, fault) in faults.enumerated() {
            let value = fault.stuckAtValue ? "1'b1" : "1'b0"
            lines.append("      \(index): force dut.\(fault.hierarchicalSignalPath) = \(value);")
        }
        lines.append("      -1: begin end")
        lines.append("      default: $fatal(1, \"DFT_REPLAY_UNKNOWN_FAULT_INDEX index=%0d\", dft_fault_index);")
        lines.append("    endcase")
    }

    private func appendFaultRelease(
        _ faults: [DFTScanPatternReplayFault],
        to lines: inout [String]
    ) {
        guard !faults.isEmpty else { return }
        lines.append("    case (dft_fault_index)")
        for (index, fault) in faults.enumerated() {
            lines.append("      \(index): release dut.\(fault.hierarchicalSignalPath);")
        }
        lines.append("      default: begin end")
        lines.append("    endcase")
    }

    private func validateSignals(_ signals: [DFTPatternSignal]) throws {
        for signal in signals where !isIdentifier(signal.name) {
            throw DFTScanPatternReplayError.harnessGenerationFailed(
                "signal \(signal.name) must be an unescaped Verilog identifier"
            )
        }
    }

    private func validateFaults(_ faults: [DFTScanPatternReplayFault]) throws {
        var faultIDs: Set<String> = []
        for fault in faults {
            guard !fault.faultID.isEmpty,
                  faultIDs.insert(fault.faultID).inserted else {
                throw DFTScanPatternReplayError.harnessGenerationFailed(
                    "fault IDs must be non-empty and unique"
                )
            }
            let segments = fault.hierarchicalSignalPath.split(
                separator: ".",
                omittingEmptySubsequences: false
            )
            guard !segments.isEmpty,
                  segments.allSatisfy({ isIdentifier(String($0)) }) else {
                throw DFTScanPatternReplayError.harnessGenerationFailed(
                    "fault path \(fault.hierarchicalSignalPath) must contain only unescaped Verilog identifiers"
                )
            }
        }
    }

    private func isIdentifier(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z_][A-Za-z0-9_$]*$"#,
            options: .regularExpression
        ) != nil
    }

    private func verilogString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private func symbolOrMissing(_ value: String?) -> String {
        value ?? "<missing>"
    }
}

private struct ReplayEvent: Sendable {
    let offset: UInt64
    let priority: Int
    let signalIndex: Int
    let statement: String
}
